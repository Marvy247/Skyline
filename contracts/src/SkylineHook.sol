// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";

import {SkylineBaseHook} from "./SkylineBaseHook.sol";
import {ISkylineHook} from "./interfaces/ISkylineHook.sol";
import {SkylineTypes} from "./libraries/SkylineTypes.sol";
import {IChainlinkFeed} from "./interfaces/IChainlinkFeed.sol";

/**
 * @title SkylineHook
 * @notice The exit-alignment enforcement point for curated liquidity on Uniswap v4.
 *
 * @dev THE DESIGN CONTRACT — read before changing anything:
 *
 *   1. The hook's obligation ledger is AUTHORITATIVE. The vault is never asked whether
 *      obligations are outstanding. If the hook trusted the vault, the hook would be decorative.
 *
 *   2. The ledger is keyed by PoolId and denominated in POOL LIQUIDITY UNITS, not token amounts
 *      and not a claim count. That makes partial settlement natural and makes cross-pool
 *      lockout impossible.
 *
 *   3. The ledger is decremented ONLY inside `afterRemoveLiquidity`, in response to a liquidity
 *      removal the PoolManager actually performed. Because a v4 position is keyed by
 *      (owner, tickLower, tickUpper, salt) and `owner` is `msg.sender` to the PoolManager, only
 *      the registered vault can remove the vault's liquidity. The ledger therefore cannot be
 *      decremented without real liquidity leaving the pool.
 *
 *   4. `hookData` is a CORRELATION channel only. It never authorises anything.
 *
 *   5. The hook must never revert because of an external call, and must never block a depositor
 *      exit.
 */
contract SkylineHook is SkylineBaseHook, ISkylineHook {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using SkylineTypes for bytes32;

    /* -------------------------------------------------------------------------- */
    /*                                  Types                                     */
    /* -------------------------------------------------------------------------- */

    /* -------------------------------------------------------------------------- */
    /*                                 Storage                                    */
    /* -------------------------------------------------------------------------- */

    /// @notice The protocol owner. May register pools and replace mandates.
    address public immutable owner;

    mapping(PoolId => SkylineTypes.PoolConfig) internal _poolConfigs;
    mapping(PoolId => SkylineTypes.Mandate) internal _mandates;

    /// @inheritdoc ISkylineHook
    mapping(PoolId => int128) public pendingLiquidity;
    /// @inheritdoc ISkylineHook
    mapping(PoolId => int128) public curatorLiquidity;
    /// @inheritdoc ISkylineHook
    mapping(PoolId => int128) public depositorLiquidity;

    /// @inheritdoc ISkylineHook
    mapping(PoolId => uint256) public nextClaimId;
    mapping(PoolId => mapping(uint256 => SkylineTypes.Claim)) internal _claims;
    /// @inheritdoc ISkylineHook
    mapping(PoolId => bool) public curatorExitApproved;

    /// @dev Tick range of the curator's position, observed from pool events.
    mapping(PoolId => int24) public curatorTickLower;
    /// @dev Tick range of the curator's position, observed from pool events.
    mapping(PoolId => int24) public curatorTickUpper;

    /// @dev Curator liquidity removed while depositor obligations were outstanding.
    mapping(PoolId => int128) public curatorAbsorbed;
    /// @dev Depositor claims those absorbed removals settled.
    mapping(PoolId => int128) public shortfallCovered;

    /// @dev Timestamp of the last risk-state evaluation.
    mapping(PoolId => uint64) public riskStateUpdatedAt;
    /// @dev High-water mark of the external mark, used to compute the strategy drawdown.
    mapping(PoolId => uint256) public referencePrice;
    /// @dev Consecutive extreme observations. A single print cannot trigger `Breached`.
    mapping(PoolId => uint8) public breachObservations;

    /// @dev Minimum acceptable staleness of a risk evaluation, in seconds.
    uint64 public constant RISK_STATE_MAX_STALENESS = 1 hours;
    /// @dev Consecutive observations above 2x the drawdown limit required before `Breached`.
    uint8 public constant BREACH_CONFIRMATIONS = 2;

    /* -------------------------------------------------------------------------- */
    /*                                Public views                                */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc ISkylineHook
    function poolConfigs(PoolId poolId) external view returns (SkylineTypes.PoolConfig memory) {
        return _poolConfigs[poolId];
    }

    /// @inheritdoc ISkylineHook
    function mandate(PoolId poolId) external view returns (SkylineTypes.Mandate memory) {
        return _mandates[poolId];
    }

    /// @inheritdoc ISkylineHook
    function claim(PoolId poolId, uint256 claimId) external view returns (SkylineTypes.Claim memory) {
        return _claims[poolId][claimId];
    }

    /* -------------------------------------------------------------------------- */
    /*                                  Events                                    */
    /* -------------------------------------------------------------------------- */

    event PoolRegistered(PoolId indexed poolId, address vault, address curator, address oracle);
    event MandateUpdated(PoolId indexed poolId, SkylineTypes.Mandate mandate);
    event ClaimRegistered(PoolId indexed poolId, uint256 indexed claimId, uint128 liquidityAmount, address depositor);
    event ClaimSettled(PoolId indexed poolId, uint256 indexed claimId, int128 liquidityRemoved, uint128 remaining);
    event ClaimExpired(PoolId indexed poolId, uint256 indexed claimId, uint128 restoredAmount);
    event CuratorExitApproved(PoolId indexed poolId);
    event CuratorExitRevoked(PoolId indexed poolId, int128 pendingLiquidity);
    event RiskStateChanged(PoolId indexed poolId, uint8 oldState, uint8 newState, uint256 drawdownBps);

    /* -------------------------------------------------------------------------- */
    /*                                  Errors                                    */
    /* -------------------------------------------------------------------------- */

    error NotOwner();
    error NotVault();
    error PoolAlreadyRegistered();
    error PoolNotRegistered();
    error ZeroAmount();
    error InvalidMandate();
    error CuratorExitBlocked(int128 pendingLiquidity);
    error CuratorExitNotApproved();
    error ExceedsShortfall();
    error FeeCapExceeded(uint24 fee, uint24 cap);
    error BelowBand(int24 tickLower, int24 bandLower);
    error AboveBand(int24 tickUpper, int24 bandUpper);
    error SkinTooLow(uint256 actualBps, uint256 requiredBps);
    error InvalidClaimStatus();
    error ClaimNotExpired();
    error ZeroSettlement();
    /// @notice A risk-increasing curator action was attempted while the risk regime is restrictive.
    error RiskStateRestricted();

    /* -------------------------------------------------------------------------- */
    /*                                Modifiers                                   */
    /* -------------------------------------------------------------------------- */

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyVault(PoolId poolId) {
        SkylineTypes.PoolConfig memory config = _poolConfigs[poolId];
        if (!config.registered) revert PoolNotRegistered();
        if (msg.sender != config.vault) revert NotVault();
        _;
    }

    /* -------------------------------------------------------------------------- */
    /*                               Construction                                 */
    /* -------------------------------------------------------------------------- */

    /// @param _poolManager The Uniswap v4 PoolManager.
    /// @param _owner The protocol owner.
    constructor(IPoolManager _poolManager, address _owner) SkylineBaseHook(_poolManager) {
        owner = _owner;
    }

    /* -------------------------------------------------------------------------- */
    /*                                Permissions                                 */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc SkylineBaseHook
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

    /* -------------------------------------------------------------------------- */
    /*                          Registration & configuration                      */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc ISkylineHook
    function registerPool(
        PoolId poolId,
        address vault,
        address curator,
        address oracle,
        SkylineTypes.Mandate calldata m
    ) external onlyOwner {
        if (_poolConfigs[poolId].registered) revert PoolAlreadyRegistered();
        if (vault == address(0) || curator == address(0)) revert ZeroAmount();
        _validateMandate(m);

        _poolConfigs[poolId] =
            SkylineTypes.PoolConfig({vault: vault, curator: curator, oracle: oracle, registered: true});
        _mandates[poolId] = m;

        emit PoolRegistered(poolId, vault, curator, oracle);
        emit MandateUpdated(poolId, m);
    }

    /// @inheritdoc ISkylineHook
    function setMandate(PoolId poolId, SkylineTypes.Mandate calldata m) external onlyOwner {
        if (!_poolConfigs[poolId].registered) revert PoolNotRegistered();
        if (curatorLiquidity[poolId] != 0 || depositorLiquidity[poolId] != 0) revert InvalidMandate();
        _validateMandate(m);

        _mandates[poolId] = m;
        emit MandateUpdated(poolId, m);
    }

    /// @inheritdoc ISkylineHook
    function setOracle(PoolId poolId, address oracle) external onlyOwner {
        if (!_poolConfigs[poolId].registered) revert PoolNotRegistered();
        _poolConfigs[poolId].oracle = oracle;
    }

    /// @dev A mandate must be internally coherent before it can be committed.
    function _validateMandate(SkylineTypes.Mandate calldata m) internal pure {
        if (m.maxFeeBps == 0 || m.maxFeeBps > 10_000) revert InvalidMandate();
        if (m.bandUpper <= m.bandLower) revert InvalidMandate();
        if (m.minSkinBps > 5_000) revert InvalidMandate();
        if (m.maxDrawdownBps == 0 || m.maxDrawdownBps > 10_000) revert InvalidMandate();
        if (m.claimTtl < 1 hours || m.claimTtl > 7 days) revert InvalidMandate();
    }

    /* -------------------------------------------------------------------------- */
    /*                                  Claims                                    */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc ISkylineHook
    function registerClaim(PoolId poolId, uint256 claimId, uint128 liquidityAmount, address depositor)
        external
        onlyVault(poolId)
        returns (bool)
    {
        if (liquidityAmount == 0) revert ZeroAmount();
        if (claimId != nextClaimId[poolId]) revert InvalidClaimStatus();
        if (depositor == address(0)) revert ZeroAmount();

        uint256 expected = nextClaimId[poolId];
        nextClaimId[poolId] = expected + 1;

        int128 before = pendingLiquidity[poolId];
        pendingLiquidity[poolId] = before + int128(liquidityAmount);

        _claims[poolId][claimId] = SkylineTypes.Claim({
            liquidityAmount: liquidityAmount,
            settledAmount: 0,
            totalLiquidityAtRegistration: uint128(_vaultLiquidity(poolId)),
            registeredAt: uint64(block.timestamp),
            expiresAt: uint64(block.timestamp) + _mandates[poolId].claimTtl,
            status: uint8(SkylineTypes.ClaimStatus.Registered),
            depositor: depositor
        });

        // A new obligation revokes any outstanding curator exit permission.
        if (before == 0 && curatorExitApproved[poolId]) {
            curatorExitApproved[poolId] = false;
            emit CuratorExitRevoked(poolId, pendingLiquidity[poolId]);
        }

        emit ClaimRegistered(poolId, claimId, liquidityAmount, depositor);
        return true;
    }

    /// @inheritdoc ISkylineHook
    function expireClaim(PoolId poolId, uint256 claimId) external returns (bool) {
        SkylineTypes.Claim storage c = _claims[poolId][claimId];
        if (
            c.status != uint8(SkylineTypes.ClaimStatus.Registered)
                && c.status != uint8(SkylineTypes.ClaimStatus.PartiallySettled)
        ) {
            revert InvalidClaimStatus();
        }
        if (block.timestamp < c.expiresAt) revert ClaimNotExpired();

        uint128 remaining = c.liquidityAmount - c.settledAmount;
        pendingLiquidity[poolId] -= int128(remaining);
        c.status = uint8(SkylineTypes.ClaimStatus.Expired);

        emit ClaimExpired(poolId, claimId, remaining);
        return true;
    }

    /// @inheritdoc ISkylineHook
    function approveCuratorExit(PoolId poolId) external onlyVault(poolId) returns (bool) {
        // The hook's ledger is the binding constraint. Vault approval alone is not sufficient.
        if (pendingLiquidity[poolId] != 0) revert CuratorExitBlocked(pendingLiquidity[poolId]);
        curatorExitApproved[poolId] = true;
        emit CuratorExitApproved(poolId);
        return true;
    }

    /* -------------------------------------------------------------------------- */
    /*                             The curator exit gate                          */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc SkylineBaseHook
    function _beforeRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        bytes calldata
    ) internal view override returns (bytes4) {
        PoolId poolId = key.toId();

        // The salt rule applies only to the REGISTERED VAULT's positions. A third party that
        // happens to use the same salt in the same pool must not be gated by our rules, and
        // must not be able to use our salt to grief themselves.
        if (params.salt != SkylineTypes.CURATOR_SALT || sender != _poolConfigs[poolId].vault) {
            // Depositor liquidity is never gated. R7: a depositor can always exit.
            return this.beforeRemoveLiquidity.selector;
        }

        SkylineTypes.Mandate memory m = _mandates[poolId];

        // --- Mandate: the curator position must stay inside its committed band ---
        if (params.tickLower < m.bandLower) revert BelowBand(params.tickLower, m.bandLower);
        if (params.tickUpper > m.bandUpper) revert AboveBand(params.tickUpper, m.bandUpper);

        int128 pending = pendingLiquidity[poolId];
        int128 delta = int128(params.liquidityDelta);

        if (pending != 0) {
            // --- Obligations are outstanding ---
            bool insolvent = pending > depositorLiquidity[poolId];

            if (!insolvent) {
                // Depositor liquidity can still cover the claims. The curator may NOT leave.
                revert CuratorExitBlocked(pending);
            }

            // --- Last resort ---
            // Depositor liquidity provably cannot cover the claims, so the curator's bond must
            // absorb the shortfall. The removal is bounded by the shortfall, so this can only
            // ever move value OUT of the curator's capital. It is not an escape hatch.
            int128 shortfall = pending - depositorLiquidity[poolId];
            int128 removal = delta < 0 ? -delta : int128(0);
            if (removal > shortfall) revert ExceedsShortfall();

            return this.beforeRemoveLiquidity.selector;
        }

        // --- No obligations outstanding ---
        if (!curatorExitApproved[poolId]) revert CuratorExitNotApproved();

        // --- Mandate: minimum skin ---
        // A full exit (post-curator liquidity of zero) is exempt: the rule constrains a curator
        // who REMAINS in the pool, not one who leaves with no obligations outstanding.
        int128 postCurator = curatorLiquidity[poolId] + delta;
        int128 postTotal = curatorLiquidity[poolId] + depositorLiquidity[poolId] + delta;
        if (postCurator != 0 && postTotal != 0) {
            uint256 actualBps = uint256(uint128(postCurator)) * 10_000 / uint256(uint128(postTotal));
            if (actualBps < m.minSkinBps) revert SkinTooLow(actualBps, m.minSkinBps);
        }

        return this.beforeRemoveLiquidity.selector;
    }

    /// @inheritdoc SkylineBaseHook
    function _afterRemoveLiquidity(
        address,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        BalanceDelta,
        BalanceDelta,
        bytes calldata hookData
    ) internal override returns (bytes4, BalanceDelta) {
        PoolId poolId = key.toId();
        int128 liquidityDelta = int128(params.liquidityDelta);

        // --- Shadow ledger: derived purely from observed pool events ---
        if (params.salt == SkylineTypes.CURATOR_SALT) {
            curatorLiquidity[poolId] += liquidityDelta;
            curatorTickLower[poolId] = params.tickLower;
            curatorTickUpper[poolId] = params.tickUpper;
        } else if (params.salt == SkylineTypes.LP_SALT) {
            depositorLiquidity[poolId] += liquidityDelta;
        }

        // --- Settlement accounting ---
        // The ledger is decremented ONLY here, in response to a removal the PoolManager actually
        // performed. `hookData` merely identifies WHICH claim the removal was for.
        (uint256 claimId, bool isSettlement) = SkylineTypes.decodeSettlement(hookData);
        if (isSettlement) {
            int128 removed = liquidityDelta < 0 ? -liquidityDelta : int128(0);
            bool wasOutstanding = pendingLiquidity[poolId] != 0;
            _applySettlement(poolId, claimId, removed);
            if (wasOutstanding && params.salt == SkylineTypes.CURATOR_SALT) {
                curatorAbsorbed[poolId] += removed;
                shortfallCovered[poolId] += removed;
            }
        }

        return (this.afterRemoveLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }

    /// @dev Applies a settled amount to a claim and decrements the obligation ledger.
    function _applySettlement(PoolId poolId, uint256 claimId, int128 removed) internal {
        if (removed <= 0) revert ZeroSettlement();

        SkylineTypes.Claim storage c = _claims[poolId][claimId];
        if (
            c.status != uint8(SkylineTypes.ClaimStatus.Registered)
                && c.status != uint8(SkylineTypes.ClaimStatus.PartiallySettled)
        ) {
            revert InvalidClaimStatus();
        }

        uint128 remaining = c.liquidityAmount - c.settledAmount;
        uint128 applied = uint128(removed) > remaining ? remaining : uint128(removed);
        if (applied == 0) revert ZeroSettlement();

        c.settledAmount += applied;
        pendingLiquidity[poolId] -= int128(applied);
        c.status = applied == remaining
            ? uint8(SkylineTypes.ClaimStatus.Settled)
            : uint8(SkylineTypes.ClaimStatus.PartiallySettled);

        emit ClaimSettled(poolId, claimId, int128(applied), remaining - applied);
    }

    /* -------------------------------------------------------------------------- */
    /*                              Add liquidity                                 */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc SkylineBaseHook
    function _beforeAddLiquidity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        bytes calldata
    ) internal view override returns (bytes4) {
        PoolId poolId = key.toId();

        if (params.salt == SkylineTypes.CURATOR_SALT && sender == _poolConfigs[poolId].vault) {
            // Risk regime: risk-INCREASING curator actions are frozen in `Restricted` and
            // `Breached`. Risk-reducing actions (a curator exit) remain available, subject to
            // the exit gate below. Depositor operations never consult the risk state.
            if (effectiveRiskState(poolId) >= uint8(SkylineTypes.RiskState.Restricted)) {
                revert RiskStateRestricted();
            }

            SkylineTypes.Mandate memory m = _mandates[poolId];
            if (params.tickLower < m.bandLower) revert BelowBand(params.tickLower, m.bandLower);
            if (params.tickUpper > m.bandUpper) revert AboveBand(params.tickUpper, m.bandUpper);
        }

        // Mandate: minimum skin, projected forward.
        //
        // The rule constrains the curator's SHARE of the vault. It applies once a bond exists,
        // so a depositor's very first deposit (before the curator has bonded) is not rejected,
        // and it applies to the curator's own bonding, so a bond that would leave the curator
        // with less than the mandated skin is rejected.
        bool isCuratorAdd = params.salt == SkylineTypes.CURATOR_SALT;
        bool hasBond = curatorLiquidity[poolId] != 0;

        if (hasBond || isCuratorAdd) {
            int128 delta = int128(params.liquidityDelta);
            int128 postCurator = curatorLiquidity[poolId] + (isCuratorAdd ? delta : int128(0));
            int128 postTotal = curatorLiquidity[poolId] + depositorLiquidity[poolId] + delta;
            uint32 minSkin = _mandates[poolId].minSkinBps;
            if (postTotal != 0) {
                if (postCurator < 0) revert SkinTooLow(0, minSkin);
                uint256 actualBps = uint256(uint128(postCurator)) * 10_000 / uint256(uint128(postTotal));
                if (actualBps < minSkin) revert SkinTooLow(actualBps, minSkin);
            }
        }

        return this.beforeAddLiquidity.selector;
    }

    /// @inheritdoc SkylineBaseHook
    function _afterAddLiquidity(
        address,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) internal override returns (bytes4, BalanceDelta) {
        PoolId poolId = key.toId();
        int128 liquidityDelta = int128(params.liquidityDelta);

        if (params.salt == SkylineTypes.CURATOR_SALT) {
            curatorLiquidity[poolId] += liquidityDelta;
            curatorTickLower[poolId] = params.tickLower;
            curatorTickUpper[poolId] = params.tickUpper;
        } else if (params.salt == SkylineTypes.LP_SALT) {
            depositorLiquidity[poolId] += liquidityDelta;
        }

        return (this.afterAddLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }

    /* -------------------------------------------------------------------------- */
    /*                                  Swap                                      */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc SkylineBaseHook
    function _beforeSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata, bytes calldata)
        internal
        view
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        // The mandate's fee cap. The hook sets the dynamic fee, so respecting the cap is
        // provable rather than promised.
        uint24 cap = _mandates[key.toId()].maxFeeBps;
        uint24 fee = cap;

        if (cap == 0) {
            // Pool not registered: do not override the fee.
            return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }
        if (fee > cap) revert FeeCapExceeded(fee, cap);

        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, fee);
    }

    /* -------------------------------------------------------------------------- */
    /*                                Risk state                                  */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc ISkylineHook
    function updateRiskState(PoolId poolId) external returns (uint8 newState) {
        if (!_poolConfigs[poolId].registered) revert PoolNotRegistered();

        SkylineTypes.Mandate memory m = _mandates[poolId];
        uint8 current = m.riskState;

        // No mark configured: there is no drawdown signal to act on. Leave the state exactly
        // as it is, and let the UI surface that the pool has no external risk monitor.
        if (_poolConfigs[poolId].oracle == address(0)) {
            riskStateUpdatedAt[poolId] = uint64(block.timestamp);
            return current;
        }

        (uint256 price, bool ok) = _readMark(poolId);
        uint256 drawdownBps;

        if (!ok) {
            // Degrade toward the MORE restrictive state only. A failed read never relaxes.
            newState =
                current < uint8(SkylineTypes.RiskState.Restricted) ? uint8(SkylineTypes.RiskState.Restricted) : current;
            breachObservations[poolId] = 0;
        } else {
            uint256 refPrice = referencePrice[poolId];
            if (refPrice == 0) {
                // First observation: establish the reference. A state that was escalated while
                // there was no reference is not relaxed until a drawdown can be computed.
                referencePrice[poolId] = price;
                newState = current;
            } else {
                // The reference is a HIGH-WATER MARK, not the first price ever seen. A recovery
                // raises it, so a later decline is measured from the peak, not from inception.
                if (price > refPrice) {
                    referencePrice[poolId] = price;
                    refPrice = price;
                }

                drawdownBps = price >= refPrice ? 0 : ((refPrice - price) * 10_000) / refPrice;

                if (drawdownBps >= uint256(m.maxDrawdownBps) * 2) {
                    // A single extreme print freezes risk-increasing curator operations but
                    // does NOT expose the bond to forfeiture. Only a confirmed breach does.
                    uint8 observations = breachObservations[poolId] + 1;
                    breachObservations[poolId] = observations;
                    newState = observations >= BREACH_CONFIRMATIONS
                        ? uint8(SkylineTypes.RiskState.Breached)
                        : uint8(SkylineTypes.RiskState.Restricted);
                } else {
                    breachObservations[poolId] = 0;
                    newState = drawdownBps >= m.maxDrawdownBps
                        ? uint8(SkylineTypes.RiskState.Restricted)
                        : uint8(SkylineTypes.RiskState.Normal);
                }
            }
        }

        if (newState != current) {
            emit RiskStateChanged(poolId, current, newState, drawdownBps);
        }

        m.riskState = newState;
        _mandates[poolId] = m;
        riskStateUpdatedAt[poolId] = uint64(block.timestamp);
        return newState;
    }

    /// @inheritdoc ISkylineHook
    function effectiveRiskState(PoolId poolId) public view returns (uint8) {
        uint8 stored = _mandates[poolId].riskState;

        // With no oracle configured there is no monitoring, so the stored state is the state.
        if (_poolConfigs[poolId].oracle == address(0)) return stored;
        if (stored >= uint8(SkylineTypes.RiskState.Breached)) return stored;
        if (stored == uint8(SkylineTypes.RiskState.Restricted)) return stored;

        // A stale or never-run evaluation means the risk regime is UNKNOWN. Treat that as
        // restrictive for curator actions. Depositor exits never read this function.
        uint64 updatedAt = riskStateUpdatedAt[poolId];
        if (updatedAt == 0 || block.timestamp > uint256(updatedAt) + RISK_STATE_MAX_STALENESS) {
            return uint8(SkylineTypes.RiskState.Restricted);
        }
        return stored;
    }

    /// @dev Reads the external mark. NEVER reverts: any failure is reported as `ok == false`.
    function _readMark(PoolId poolId) internal view returns (uint256 price, bool ok) {
        address oracle = _poolConfigs[poolId].oracle;
        if (oracle == address(0)) return (0, false);

        try IChainlinkFeed(oracle).latestRoundData() returns (
            uint80 roundId, int256 answer, uint256, uint256 updatedAt, uint80 answeredInRound
        ) {
            if (answer <= 0) return (0, false);
            if (updatedAt == 0) return (0, false);
            // Check the age without adding to an untrusted timestamp.
            if (block.timestamp > updatedAt && block.timestamp - updatedAt > RISK_STATE_MAX_STALENESS) {
                return (0, false);
            }
            // The round must be complete: Chainlink sets answeredInRound below roundId when
            // the current round has not been answered yet.
            if (answeredInRound < roundId) return (0, false);
            return (uint256(answer), true);
        } catch {
            return (0, false);
        }
    }

    /// @inheritdoc ISkylineHook
    function riskState(PoolId poolId) external view returns (uint8) {
        return _mandates[poolId].riskState;
    }

    /* -------------------------------------------------------------------------- */
    /*                                Views                                       */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc ISkylineHook
    function isCuratorExitBlocked(PoolId poolId) external view returns (bool) {
        return _isCuratorExitBlocked(poolId);
    }

    /// @dev Whether the curator's exit is currently blocked.
    function _isCuratorExitBlocked(PoolId poolId) internal view returns (bool) {
        int128 pending = pendingLiquidity[poolId];
        if (pending == 0) return false;
        // Blocked unless depositor liquidity provably cannot cover the claims.
        return pending <= depositorLiquidity[poolId];
    }

    /// @inheritdoc ISkylineHook
    function verifyCep(PoolId poolId)
        external
        view
        returns (bool cepHolds, int128 pending, int128 curatorLiquidity_, bool curatorMayExit)
    {
        pending = pendingLiquidity[poolId];
        curatorLiquidity_ = curatorLiquidity[poolId];

        bool blocked = _isCuratorExitBlocked(poolId);
        curatorMayExit = !blocked && pending == 0 && curatorExitApproved[poolId];

        // The tripwire: curator liquidity removed while obligations were outstanding must never
        // exceed the claims those removals settled.
        cepHolds = curatorAbsorbed[poolId] <= shortfallCovered[poolId];
    }

    /// @inheritdoc ISkylineHook
    function verifyCuratorBond(PoolId poolId) external view returns (int128 poolDerived, int128 recorded) {
        recorded = curatorLiquidity[poolId];

        address vault = _poolConfigs[poolId].vault;
        int24 tickLower = curatorTickLower[poolId];
        int24 tickUpper = curatorTickUpper[poolId];
        if (vault == address(0) || tickUpper <= tickLower) return (0, recorded);

        (uint128 liquidity,,) =
            poolManager.getPositionInfo(poolId, vault, tickLower, tickUpper, SkylineTypes.CURATOR_SALT);
        poolDerived = int128(liquidity);
    }

    /// @inheritdoc ISkylineHook
    function verifyPending(PoolId poolId) external view returns (int128 derived, int128 recorded) {
        recorded = pendingLiquidity[poolId];

        uint256 n = nextClaimId[poolId];
        for (uint256 i = 0; i < n; i++) {
            SkylineTypes.Claim memory c = _claims[poolId][i];
            if (
                c.status == uint8(SkylineTypes.ClaimStatus.Registered)
                    || c.status == uint8(SkylineTypes.ClaimStatus.PartiallySettled)
            ) {
                derived += int128(c.liquidityAmount - c.settledAmount);
            }
        }
    }

    /// @dev Total vault-side liquidity, from the shadow counters.
    function _vaultLiquidity(PoolId poolId) internal view returns (int128 total) {
        total = curatorLiquidity[poolId] + depositorLiquidity[poolId];
    }

    /// @notice The vault's own view of the pool's liquidity, for cross-checking.
    /// @dev Read from the pool, not from the shadow counters.
    function verifyVaultLiquidity(PoolId poolId) external view returns (int128 poolDerived) {
        address vault = _poolConfigs[poolId].vault;
        int24 tickLower = curatorTickLower[poolId];
        int24 tickUpper = curatorTickUpper[poolId];
        if (vault == address(0) || tickUpper <= tickLower) return 0;

        (uint128 curator,,) =
            poolManager.getPositionInfo(poolId, vault, tickLower, tickUpper, SkylineTypes.CURATOR_SALT);
        (uint128 depositor,,) = poolManager.getPositionInfo(poolId, vault, tickLower, tickUpper, SkylineTypes.LP_SALT);
        poolDerived = int128(curator) + int128(depositor);
    }
}
