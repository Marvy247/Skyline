// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

import {IAutomationCompatible} from "./interfaces/IAutomationCompatible.sol";
import {ISkylineHook} from "./interfaces/ISkylineHook.sol";
import {ISkylineVault} from "./interfaces/ISkylineVault.sol";

/**
 * @title SkylineKeeper
 * @notice A Chainlink Automation-compatible keeper that refreshes the risk regime and serves
 *         due withdrawal claims.
 *
 * @dev WHAT THIS IS: an optimisation. It saves a human from calling two permissionless
 *      functions. It is NOT a dependency:
 *        - `hook.updateRiskState` is permissionless;
 *        - `vault.settleClaims` is permissionless;
 *        - depositor exits work when the keeper has never run and when the oracle is down.
 *
 *      WHAT THIS IS NOT: an authority. `performUpkeep` recomputes both conditions from
 *      authoritative state and ignores the hints in `performData`. A caller cannot use the
 *      keeper to skip a check or to authorize a curator action.
 *
 *      The keeper only ever tightens the risk regime (via `updateRiskState`, which degrades
 *      toward the more restrictive state) and serves claims. It never touches curator
 *      liquidity, the mandate, or the oracle address.
 */
contract SkylineKeeper is IAutomationCompatible {
    /// @notice The hook whose risk state is refreshed.
    ISkylineHook public immutable hook;
    /// @notice The vault whose claims are served.
    ISkylineVault public immutable vault;
    /// @notice The pool watched by this keeper.
    PoolId public immutable poolId;
    /// @notice Maximum claims served per upkeep, bounding the gas cost of one run.
    uint256 public immutable maxClaimsPerRun;

    constructor(ISkylineHook hook_, ISkylineVault vault_, PoolId poolId_, uint256 maxClaimsPerRun_) {
        if (address(hook_) == address(0) || address(vault_) == address(0)) revert ZeroAddress();
        if (maxClaimsPerRun_ == 0) revert ZeroAmount();
        hook = hook_;
        vault = vault_;
        poolId = poolId_;
        maxClaimsPerRun = maxClaimsPerRun_;
    }

    error ZeroAddress();
    error ZeroAmount();

    /// @inheritdoc IAutomationCompatible
    function checkUpkeep(bytes calldata) external view override returns (bool upkeepNeeded, bytes memory performData) {
        bool riskDue = _riskDue();
        bool claimsDue = vault.outstandingClaims() != 0;
        upkeepNeeded = riskDue || claimsDue;
        performData = abi.encode(riskDue, claimsDue);
    }

    /// @inheritdoc IAutomationCompatible
    function performUpkeep(bytes calldata) external override {
        // `performData` is deliberately ignored: it is an untrusted hint. The keeper re-reads
        // the authoritative state, so a stale or forged hint cannot change what happens.
        if (_riskDue()) hook.updateRiskState(poolId);

        if (vault.outstandingClaims() != 0) {
            // Settlement is a best-effort service. A failure here must not block the risk
            // refresh above, and it must never be treated as a reason to restrict a depositor:
            // anyone can call `settleClaims` directly, and the vault's own exit ladder does not
            // depend on this keeper.
            try vault.settleClaims(maxClaimsPerRun) {} catch {}
        }
    }

    /// @dev Whether the stored risk evaluation is older than the hook's freshness window.
    function _riskDue() internal view returns (bool) {
        uint64 updatedAt = hook.riskStateUpdatedAt(poolId);
        return updatedAt == 0 || block.timestamp > uint256(updatedAt) + hook.RISK_STATE_MAX_STALENESS();
    }
}
