// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {SkylineTypes} from "../libraries/SkylineTypes.sol";

/**
 * @title ISkylineHook
 * @notice The Skyline enforcement point: the authoritative obligation ledger and the curator
 *         exit gate.
 * @dev The hook's ledger is authoritative. The vault is NEVER asked whether obligations are
 *      outstanding; the hook answers from its own state, and decrements that state only from
 *      liquidity removals it observes. This is what makes the hook load-bearing rather than
 *      decorative.
 */
interface ISkylineHook {
    /* -------------------------------------------------------------------------- */
    /*                             Registration & config                        */
    /* -------------------------------------------------------------------------- */

    /// @notice Registers a pool. One-shot per pool id, before any liquidity is added.
    function registerPool(
        PoolId poolId,
        address vault,
        address curator,
        address oracle,
        SkylineTypes.Mandate calldata mandate
    ) external;

    /// @notice Replaces the mandate. Only permitted while the pool holds no liquidity.
    function setMandate(PoolId poolId, SkylineTypes.Mandate calldata mandate) external;

    /// @notice Sets the external mark source. May be address(0) to disable drawdown monitoring.
    function setOracle(PoolId poolId, address oracle) external;

    /* -------------------------------------------------------------------------- */
    /*                                 Claims                                    */
    /* -------------------------------------------------------------------------- */

    /// @notice Records a depositor withdrawal claim and increments the obligation ledger.
    /// @dev Callable only by the pool's registered vault.
    function registerClaim(PoolId poolId, uint256 claimId, uint128 liquidityAmount, address depositor)
        external
        returns (bool);

    /// @notice Cancels a claim whose TTL has elapsed and restores the depositor's entitlement.
    /// @dev Permissionless once the claim has expired.
    function expireClaim(PoolId poolId, uint256 claimId) external returns (bool);

    /// @notice Grants the curator permission to remove curator-bonded liquidity.
    /// @dev Requires an EMPTY obligation ledger. The ledger is the binding constraint; this
    ///      approval alone is not sufficient.
    function approveCuratorExit(PoolId poolId) external returns (bool);

    /* -------------------------------------------------------------------------- */
    /*                                  Views                                    */
    /* -------------------------------------------------------------------------- */

    /// @notice Outstanding depositor obligations for a pool, in pool liquidity units.
    function pendingLiquidity(PoolId poolId) external view returns (int128);

    /// @notice Curator-bonded liquidity in the pool, in pool liquidity units.
    function curatorLiquidity(PoolId poolId) external view returns (int128);

    /// @notice Depositor liquidity in the pool, in pool liquidity units.
    function depositorLiquidity(PoolId poolId) external view returns (int128);

    /// @notice The next claim id for a pool. Monotonic, never reused.
    function nextClaimId(PoolId poolId) external view returns (uint256);

    /// @notice The current risk state of a pool.
    function riskState(PoolId poolId) external view returns (uint8);

    /// @notice The risk state after applying evaluation staleness.
    /// @dev Returns `Restricted` when an oracle is configured but the last evaluation is older
    ///      than `RISK_STATE_MAX_STALENESS`, or has never run. Never used on a depositor path.
    function effectiveRiskState(PoolId poolId) external view returns (uint8);

    /// @notice Timestamp of the last risk-state evaluation.
    function riskStateUpdatedAt(PoolId poolId) external view returns (uint64);

    /// @notice Consecutive extreme observations recorded for a pool.
    function breachObservations(PoolId poolId) external view returns (uint8);

    /// @notice Maximum age of a risk-state evaluation before curator actions are restricted.
    function RISK_STATE_MAX_STALENESS() external view returns (uint64);

    /// @notice Number of consecutive extreme observations required before `Breached`.
    function BREACH_CONFIRMATIONS() external view returns (uint8);

    /// @notice Whether the curator's exit is currently blocked.
    function isCuratorExitBlocked(PoolId poolId) external view returns (bool);

    /// @notice Whether the curator's exit has been approved.
    function curatorExitApproved(PoolId poolId) external view returns (bool);

    /// @notice A claim's full record.
    function claim(PoolId poolId, uint256 claimId) external view returns (SkylineTypes.Claim memory);

    /// @notice A pool's mandate.
    function mandate(PoolId poolId) external view returns (SkylineTypes.Mandate memory);

    /// @notice A pool's configuration.
    function poolConfigs(PoolId poolId) external view returns (SkylineTypes.PoolConfig memory);

    /* -------------------------------------------------------------------------- */
    /*                              Verification                                 */
    /* -------------------------------------------------------------------------- */

    /// @notice Whether Curator Exit Parity currently holds, and the figures behind it.
    /// @dev Recomputed from the hook's own ledger. Anyone can call this.
    function verifyCep(PoolId poolId)
        external
        view
        returns (bool cepHolds, int128 pending, int128 curatorLiquidity_, bool curatorMayExit);

    /// @notice The curator's bonded liquidity, recomputed independently from pool state.
    function verifyCuratorBond(PoolId poolId) external view returns (int128 poolDerived, int128 recorded);

    /// @notice The outstanding obligation, recomputed independently from the claim set.
    function verifyPending(PoolId poolId) external view returns (int128 derived, int128 recorded);

    /* -------------------------------------------------------------------------- */
    /*                              Risk state                                   */
    /* -------------------------------------------------------------------------- */

    /// @notice Recomputes the risk state from the external mark and the drawdown limit.
    /// @dev Permissionless. Degrades only toward the more restrictive state.
    function updateRiskState(PoolId poolId) external returns (uint8 newState);
}
