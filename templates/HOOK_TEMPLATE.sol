// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title <HookName>
 * @notice <One sentence: what this hook enforces, and where in the pool lifecycle.>
 * @dev <The invariant this hook is responsible for, stated precisely.>
 *
 * DESIGN CONTRACT — read before changing anything:
 *   - The hook is the AUTHORITY for <X>. The vault is never asked about <X>.
 *   - State is keyed by PoolId. Never global.
 *   - `hookData` is untrusted input. It may correlate a call; it may never authorise one.
 *   - The hook must never revert because of an external call.
 *   - The hook must never block a depositor exit.
 *
 * Position attribution (verify against the pinned v4-core tag):
 *   positionKey = keccak256(abi.encodePacked(owner, tickLower, tickUpper, salt))
 *   owner       = msg.sender to the PoolManager
 *   beforeRemoveLiquidity receives (sender, key, params{salt}, hookData)
 */

import {BaseHook} from "uniswap-hooks/src/base/BaseHook.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/src/types/PoolOperation.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";

contract <HookName> is BaseHook {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    /* ------------------------------------------------------------------ */
    /*                              Types                                 */
    /* ------------------------------------------------------------------ */

    struct PoolConfig {
        address vault;
        address curator;
        address oracle;
        bool registered;
    }

    /* ------------------------------------------------------------------ */
    /*                             Storage                               */
    /* ------------------------------------------------------------------ */

    address public immutable owner;

    mapping(PoolId => PoolConfig) public poolConfigs;
    mapping(PoolId => int128) public <ledger>;
    mapping(PoolId => mapping(uint256 => <Claim>)) public <claims>;

    /* ------------------------------------------------------------------ */
    /*                              Events                                */
    /* ------------------------------------------------------------------ */

    event PoolRegistered(PoolId indexed poolId, address vault, address curator);
    event <SomethingRecorded>(PoolId indexed poolId, uint256 indexed id, uint128 amount);

    /* ------------------------------------------------------------------ */
    /*                             Errors                                */
    /* ------------------------------------------------------------------ */

    error PoolAlreadyRegistered();
    error PoolNotRegistered();
    error NotVault();
    error NotOwner();
    error <TheError>(<Context>);

    /* ------------------------------------------------------------------ */
    /*                            Modifiers                              */
    /* ------------------------------------------------------------------ */

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyVault(PoolId poolId) {
        if (poolConfigs[poolId].vault == address(0) || msg.sender != poolConfigs[poolId].vault) {
            revert NotVault();
        }
        _;
    }

    /* ------------------------------------------------------------------ */
    /*                           Construction                             */
    /* ------------------------------------------------------------------ */

    constructor(address owner_) BaseHook(owner_) {
        owner = owner_;
    }

    /* ------------------------------------------------------------------ */
    /*                             Permissions                            */
    /* ------------------------------------------------------------------ */

    /// @inheritdoc BaseHook
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: true,
            afterAddLiquidity: true,
            beforeRemoveLiquidity: true,
            afterRemoveLiquidity: true,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    /* ------------------------------------------------------------------ */
    /*                         Registration & config                      */
    /* ------------------------------------------------------------------ */

    /// @notice Registers a pool. One-shot, before any liquidity is added.
    function registerPool(PoolId poolId, address vault, address curator, address oracle)
        external
        onlyOwner
    {
        if (poolConfigs[poolId].registered) revert PoolAlreadyRegistered();
        poolConfigs[poolId] = PoolConfig({
            vault: vault,
            curator: curator,
            oracle: oracle,
            registered: true
        });
        emit PoolRegistered(poolId, vault, curator);
    }

    /* ------------------------------------------------------------------ */
    /*                          The core gate                             */
    /* ------------------------------------------------------------------ */

    /// @notice Blocks removals that violate the protocol's ordering rule.
    /// @dev <state the exact rule, and the exception conditions>
    function _beforeRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        bytes calldata hookData
    ) internal override returns (bytes4) {
        PoolId poolId = key.toId();

        // The rule. Example shape:
        //
        // if (params.salt == CURATOR_SALT) {
        //     bool insolvent = pendingLiquidity[poolId] > depositorLiquidity[poolId];
        //     if (!insolvent) {
        //         if (pendingLiquidity[poolId] != 0) revert <TheError>(pendingLiquidity[poolId]);
        //         if (!curatorExitApproved[poolId]) revert <TheError>();
        //     } else {
        //         int128 shortfall = pendingLiquidity[poolId] - depositorLiquidity[poolId];
        //         if (-params.liquidityDelta > shortfall) revert <TheError>();
        //     }
        // }

        return this.beforeRemoveLiquidity.selector;
    }

    /* ------------------------------------------------------------------ */
    /*                          Shadow accounting                         */
    /* ------------------------------------------------------------------ */

    /// @notice Maintains the hook's own view of pool liquidity, from observed events only.
    function _afterModifyLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        BalanceDelta delta,
        BalanceDelta feesAccrued,
        bytes calldata hookData
    ) internal override returns (bytes4, BalanceDelta) {
        PoolId poolId = key.toId();
        // <update the shadow counters>
        return (this.afterModifyLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }

    /* ------------------------------------------------------------------ */
    /*                             Swap path                              */
    /* ------------------------------------------------------------------ */

    /// @notice Sets a dynamic fee, capped by the mandate.
    function _beforeSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata hookData
    ) internal override returns (BeforeSwapDelta, uint24) {
        uint24 fee = <compute>;
        // if (fee > mandate.maxFeeBps) revert <TheError>(fee, mandate.maxFeeBps);
        return (BeforeSwapDeltaLibrary.ZERO_DELTA, fee);
    }

    /* ------------------------------------------------------------------ */
    /*                          Oracle (optional)                        */
    /* ------------------------------------------------------------------ */

    /// @dev Never reverts. Returns ok = false on any failure, and the caller
    ///      degrades toward the more restrictive state.
    function _readMark(PoolId poolId) internal view returns (uint256 mark, bool ok) {
        address oracle = poolConfigs[poolId].oracle;
        if (oracle == address(0)) return (0, false);
        // try oracle.latestRoundData() returns (...) { ... } catch { return (0, false); }
        return (0, false);
    }

    /* ------------------------------------------------------------------ */
    /*                        Independent verification                    */
    /* ------------------------------------------------------------------ */

    /// @notice Recomputes the protocol's state from pool state, independently of the vault.
    function verify<Something>(PoolId poolId) external view returns (bool ok, int128 derived, int128 recorded) {
        return (true, 0, 0);
    }
}
