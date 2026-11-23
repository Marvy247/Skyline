// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {SqrtPriceMath} from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";

import {ISkylineHook} from "./interfaces/ISkylineHook.sol";
import {ISkylineVault} from "./interfaces/ISkylineVault.sol";
import {SkylineTypes} from "./libraries/SkylineTypes.sol";

/**
 * @title SkylineVault
 * @notice Depositor accounting, the withdrawal claim queue, settlement and the curator bond for
 *         one Uniswap v4 strategy pool.
 *
 * @dev THE VAULT IS NOT THE ENFORCEMENT POINT.
 *
 *      The hook owns the obligation ledger and the curator exit gate. This contract never
 *      decides whether the curator may leave; it asks the hook, and the hook answers from its
 *      own state. If this contract were malicious or buggy, the ordering property would still
 *      hold, because the gate lives below the vault in the PoolManager.
 *
 *      Two positions, distinguished only by `salt`:
 *        - LP_SALT      : depositor capital
 *        - CURATOR_SALT : the curator's bonded capital
 *
 *      `totalAssets()` deliberately EXCLUDES the curator bond. The bond is a carve-out of the
 *      vault's own liquidity, economically owed to the curator and subordinated to depositor
 *      claims.
 *
 *      LIQUIDITY MODEL. The vault's asset is the pool's currency0. A concentrated position that
 *      straddles the price needs both currencies, so a deposit is split: half is swapped into
 *      the pool's other currency and half funds the currency0 side. The liquidity is sized
 *      against whichever side binds first, with a safety margin, so the vault never promises
 *      liquidity it cannot pay for. Positions are valued in currency0 only; any currency1 the
 *      position accrues is retained by the vault as a surplus and is never counted in
 *      `totalAssets()`. This is deliberately conservative.
 */
contract SkylineVault is IUnlockCallback, ISkylineVault, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    /* -------------------------------------------------------------------------- */
    /*                                  Types                                     */
    /* -------------------------------------------------------------------------- */

    /// @notice A depositor's claim, as tracked by the vault.
    struct ClaimRecord {
        uint256 shares; // shares reserved for this claim
        uint128 liquidityAmount; // pool liquidity units owed
        uint128 settledLiquidity; // pool liquidity units already delivered
        uint256 assetsOwed; // the asset value promised at registration
        uint256 assetsPaid; // the asset value actually delivered
        address depositor;
        uint64 createdAt;
        uint8 status; // see SkylineTypes.ClaimStatus
    }

    /// @dev The kinds of pool action a single unlock can perform.
    enum Action {
        ModifyLiquidity,
        Swap
    }

    /// @dev Parameters for a single unlock callback.
    struct CallbackData {
        PoolKey key;
        Action action;
        bytes32 salt;
        int24 tickLower;
        int24 tickUpper;
        int256 liquidityDelta;
        bool zeroForOne;
        int256 amountSpecified;
        bytes hookData;
    }

    /* -------------------------------------------------------------------------- */
    /*                                 Storage                                    */
    /* -------------------------------------------------------------------------- */

    /// @notice The vault asset (e.g. USDC).
    IERC20 public immutable asset;
    /// @notice The Uniswap v4 PoolManager.
    IPoolManager public immutable poolManager;
    /// @notice The Skyline hook — the enforcement point.
    ISkylineHook public immutable hook;
    /// @notice The curator of record.
    address public immutable curator;
    /// @notice Where performance fees are minted.
    address public immutable feeRecipient;

    /// @notice The pool this vault manages.
    PoolKey public poolKey;
    /// @notice The pool id.
    PoolId public poolId;

    /// @notice Current tick range of the vault's positions.
    int24 public tickLower;
    /// @notice Current tick range of the vault's positions.
    int24 public tickUpper;
    /// @notice Liquidity currently held under LP_SALT.
    uint128 public depositorLiquidity;
    /// @notice Liquidity currently held under CURATOR_SALT.
    uint128 public curatorLiquidity;

    /// @notice Total depositor shares outstanding.
    uint256 public totalSupply;
    /// @notice High-water mark, per share, scaled by 1e18.
    uint256 public highWaterMark;
    /// @notice Performance fee, in bps.
    uint16 public perfFeeBps;

    /// @notice Uncovered claim amount charged to the curator, in asset units.
    uint256 public uncoveredShortfall;
    /// @notice The curator's bond claim, in asset units.
    uint256 public curatorBondValue;

    /// @notice Next claim id, mirrored from the hook.
    uint256 public nextClaimId;
    /// @notice Number of open claims.
    uint256 public openClaimCount;
    /// @notice Timestamp of the curator's last exit request.
    uint64 public lastCuratorExitRequest;
    /// @notice Whether the curator's exit has been requested.
    bool public curatorExitRequested;

    /// @notice Claims, keyed by claim id.
    mapping(uint256 => ClaimRecord) public claims;
    /// @notice Shares per depositor.
    mapping(address => uint256) public balanceOf;
    /// @notice Shares reserved against open claims.
    mapping(address => uint256) public reservedShares;

    /// @dev Cooldown between curator exit requests.
    uint64 public constant CURATOR_EXIT_COOLDOWN = 1 hours;
    /// @dev Minimum claim size, in liquidity units.
    uint128 public constant MIN_CLAIM_LIQUIDITY = 1;
    /// @dev Maximum open claims per depositor.
    uint256 public constant MAX_OPEN_CLAIMS = 3;
    /// @dev The unit used when sizing liquidity from a deposit.
    uint256 public constant LIQUIDITY_UNIT = 1e18;
    /// @dev Safety margin applied when sizing liquidity, in percent.
    uint256 public constant LIQUIDITY_MARGIN_BPS = 9_990;

    /* -------------------------------------------------------------------------- */
    /*                                  Events                                    */
    /* -------------------------------------------------------------------------- */

    event Deposited(address indexed sender, address indexed receiver, uint256 assets, uint256 shares);
    event WithdrawalRequested(
        address indexed depositor, uint256 indexed claimId, uint256 shares, uint128 liquidityAmount
    );
    event ClaimsSettled(uint256 count, uint256 assetsPaid);
    event ClaimCancelled(address indexed depositor, uint256 indexed claimId, uint256 sharesRestored);
    event CuratorBonded(address indexed curator, uint256 assets, uint128 liquidityAdded);
    event CuratorExitRequested(address indexed curator, uint64 timestamp);
    event CuratorExited(address indexed curator, uint256 proceeds, uint256 shortfallNetted);
    event ShortfallAbsorbed(address indexed curator, uint256 amount, uint256 remainingShortfall);
    event PerformanceFeeAccrued(uint256 feeShares, uint256 hwm, uint256 navPerShare);
    event PerformanceFeeForfeited(uint256 hwm, uint256 navPerShare);

    /* -------------------------------------------------------------------------- */
    /*                                  Errors                                    */
    /* -------------------------------------------------------------------------- */

    error ZeroAmount();
    error InsufficientShares();
    error InsufficientAssets();
    error ClaimLimitExceeded();
    error MinClaimSize();
    error NothingToSettle();
    error CoolingOff();
    error NotCurator();
    error InvalidTickRange();
    error InvalidClaimStatus();
    error AssetMustBeCurrency0();
    error InsufficientCurrency1();
    /// @notice A risk-increasing curator action was attempted while the risk regime is restrictive.
    error RiskStateRestricted();

    /* -------------------------------------------------------------------------- */
    /*                               Construction                                 */
    /* -------------------------------------------------------------------------- */

    /// @param asset_ The vault asset. Must be the pool's currency0.
    /// @param poolManager_ The Uniswap v4 PoolManager.
    /// @param hook_ The Skyline hook.
    /// @param key_ The pool this vault manages.
    /// @param curator_ The curator of record.
    /// @param feeRecipient_ Where performance fees are minted.
    /// @param perfFeeBps_ Performance fee in bps.
    /// @param tickLower_ The tick range lower bound.
    /// @param tickUpper_ The tick range upper bound.
    constructor(
        IERC20 asset_,
        IPoolManager poolManager_,
        ISkylineHook hook_,
        PoolKey memory key_,
        address curator_,
        address feeRecipient_,
        uint16 perfFeeBps_,
        int24 tickLower_,
        int24 tickUpper_
    ) {
        if (curator_ == address(0) || feeRecipient_ == address(0)) revert ZeroAmount();
        if (tickUpper_ <= tickLower_) revert InvalidTickRange();
        if (Currency.unwrap(key_.currency0) != address(asset_)) revert AssetMustBeCurrency0();

        asset = asset_;
        poolManager = poolManager_;
        hook = hook_;
        poolKey = key_;
        poolId = key_.toId();
        curator = curator_;
        feeRecipient = feeRecipient_;
        perfFeeBps = perfFeeBps_;
        tickLower = tickLower_;
        tickUpper = tickUpper_;
        highWaterMark = 1e18;
    }

    modifier onlyCurator() {
        if (msg.sender != curator) revert NotCurator();
        _;
    }

    /* -------------------------------------------------------------------------- */
    /*                                 Depositing                                 */
    /* -------------------------------------------------------------------------- */

    /// @notice Deposits assets and mints shares.
    /// @param assets The amount of vault asset to deposit.
    /// @param receiver The share recipient.
    /// @return shares The shares minted.
    function deposit(uint256 assets, address receiver) external nonReentrant returns (uint256 shares) {
        if (assets == 0) revert ZeroAmount();

        shares = _previewDeposit(assets);
        if (shares == 0) revert ZeroAmount();

        asset.safeTransferFrom(msg.sender, address(this), assets);

        _addLiquidityFromAssets(SkylineTypes.LP_SALT, assets);

        totalSupply += shares;
        balanceOf[receiver] += shares;

        _updateHwm();
        emit Deposited(msg.sender, receiver, assets, shares);
    }

    /// @notice The curator posts (or tops up) their bonded capital.
    /// @param assets The amount of vault asset to bond.
    /// @return liquidityAdded The liquidity added.
    function curatorDeposit(uint256 assets) external onlyCurator nonReentrant returns (uint128 liquidityAdded) {
        if (assets == 0) revert ZeroAmount();

        // A curator may not increase exposure while the external risk regime says the strategy
        // is outside its mandate. Exits are unaffected. The hook enforces this too; this check
        // simply produces a direct error instead of a wrapped callback failure.
        if (hook.effectiveRiskState(poolId) >= uint8(SkylineTypes.RiskState.Restricted)) {
            revert RiskStateRestricted();
        }

        asset.safeTransferFrom(msg.sender, address(this), assets);

        liquidityAdded = _addLiquidityFromAssets(SkylineTypes.CURATOR_SALT, assets);
        curatorBondValue += assets;

        emit CuratorBonded(curator, assets, liquidityAdded);
    }

    /* -------------------------------------------------------------------------- */
    /*                             Withdrawal requests                           */
    /* -------------------------------------------------------------------------- */

    /// @notice Registers a withdrawal claim. The hook records the obligation immediately and the
    ///         curator's exit is locked from that moment.
    /// @param shares The shares to redeem.
    /// @return claimId The new claim id.
    function requestWithdraw(uint256 shares) external nonReentrant returns (uint256 claimId) {
        uint256 userShares = balanceOf[msg.sender];
        if (shares == 0 || shares > userShares - reservedShares[msg.sender]) revert InsufficientShares();
        if (_openClaimsOf(msg.sender) >= MAX_OPEN_CLAIMS) revert ClaimLimitExceeded();

        uint256 assets = _previewRedeem(shares);
        uint128 liquidityAmount = _liquidityForAssets(assets);
        if (liquidityAmount < MIN_CLAIM_LIQUIDITY) revert MinClaimSize();

        // The depositor is promised the value of the liquidity that will actually be removed,
        // measured now. Any later difference is a real loss, not a sizing artifact.
        uint256 owed = _assetsForLiquidity(liquidityAmount);

        // Reserve the shares so they cannot be spent twice.
        balanceOf[msg.sender] = userShares - shares;
        reservedShares[msg.sender] += shares;

        claimId = nextClaimId;
        nextClaimId = claimId + 1;

        claims[claimId] = ClaimRecord({
            shares: shares,
            liquidityAmount: liquidityAmount,
            settledLiquidity: 0,
            assetsOwed: owed,
            assetsPaid: 0,
            depositor: msg.sender,
            createdAt: uint64(block.timestamp),
            status: uint8(SkylineTypes.ClaimStatus.Registered)
        });
        openClaimCount++;

        // The hook's ledger is authoritative. This call is what makes the curator's exit blocked.
        hook.registerClaim(poolId, claimId, liquidityAmount, msg.sender);

        emit WithdrawalRequested(msg.sender, claimId, shares, liquidityAmount);
    }

    /// @notice Serves due claims, FIFO.
    /// @dev Permissionless. The three stages of the exit ladder are implemented here:
    ///      1. depositor liquidity serves the claim;
    ///      2. the curator's bond absorbs any shortfall;
    ///      3. if total claims exceed total available liquidity, every open claim receives a
    ///         PRO-RATA share of what is left, so the first claimant cannot extract everything
    ///         while the others are left with nothing.
    /// @param maxClaims The maximum number of claims to process.
    /// @return settled The number of claims served.
    function settleClaims(uint256 maxClaims) external nonReentrant returns (uint256 settled) {
        uint256 totalRemaining = _totalOutstandingLiquidity();
        uint256 available = uint256(depositorLiquidity) + uint256(curatorLiquidity);
        bool proRata = totalRemaining > available;

        uint256 processed;
        for (uint256 i = 0; i < maxClaims && processed < nextClaimId; i++) {
            ClaimRecord storage c = claims[i];
            if (
                c.status != uint8(SkylineTypes.ClaimStatus.Registered)
                    && c.status != uint8(SkylineTypes.ClaimStatus.PartiallySettled)
            ) {
                continue;
            }
            uint128 remaining = c.liquidityAmount - c.settledLiquidity;
            if (remaining == 0) continue;

            uint128 take;
            if (proRata) {
                take = uint128((available * remaining) / totalRemaining);
                if (take == 0) continue;
            } else {
                take = remaining > available ? uint128(available) : remaining;
                if (take == 0) break;
            }

            uint256 paid = _serve(i, take);
            settled++;
            processed++;
            emit ClaimsSettled(1, paid);
        }

        if (settled == 0) revert NothingToSettle();
    }

    /// @dev Serves `take` liquidity units of a claim, drawing on depositor liquidity first and
    ///      then on the curator's bond.
    /// @return assetsPaid The asset amount delivered to the depositor.
    function _serve(uint256 claimId, uint128 take) internal returns (uint256 assetsPaid) {
        ClaimRecord storage c = claims[claimId];
        bytes memory tag = SkylineTypes.encodeSettlement(claimId);
        IERC20 other = IERC20(Currency.unwrap(_currency1()));

        uint128 remainingBefore = c.liquidityAmount - c.settledLiquidity;
        if (take > remainingBefore) take = remainingBefore;

        // Burn the shares that this settlement actually redeems. Doing it per-serve (rather
        // than only on full settlement) is what keeps `totalSupply` honest after a partial
        // pro-rata settlement, and what stops an expired claim from restoring shares that
        // have already been paid for.
        _burnSettledShares(c, take, remainingBefore);
        c.settledLiquidity += take;

        uint256 balanceBefore = asset.balanceOf(address(this));
        uint256 otherBefore = other.balanceOf(address(this));

        // --- Stage 1: depositor liquidity ---
        uint128 fromDepositor = take > depositorLiquidity ? depositorLiquidity : take;
        if (fromDepositor > 0) {
            _removeLiquidity(SkylineTypes.LP_SALT, fromDepositor, tag);
        }

        // --- Stage 2: the curator's bond absorbs the shortfall ---
        uint128 fromBond = take - fromDepositor;
        if (fromBond > 0) {
            _removeLiquidity(SkylineTypes.CURATOR_SALT, fromBond, tag);
            uint256 received = asset.balanceOf(address(this)) - balanceBefore;
            uint256 consumed = received < curatorBondValue ? received : curatorBondValue;
            curatorBondValue -= consumed;
            uncoveredShortfall += consumed;
            emit ShortfallAbsorbed(curator, consumed, uncoveredShortfall);
        }

        // The removal returned both pool currencies. Depositors are paid in the vault's asset, so
        // the currency1 side is converted first.
        uint256 otherReceived = other.balanceOf(address(this)) - otherBefore;
        if (otherReceived > 0) {
            _swapExactInput(otherReceived, false);
        }

        assetsPaid = asset.balanceOf(address(this)) - balanceBefore;
        c.assetsPaid += assetsPaid;
        if (assetsPaid > 0) {
            asset.safeTransfer(c.depositor, assetsPaid);
        }

        if (c.settledLiquidity >= c.liquidityAmount) {
            // The strategy may have lost value between registration and settlement. Whatever the
            // depositor was promised but did not receive is charged to the curator's bond: that is
            // what "skin in the game" means.
            if (c.assetsOwed > c.assetsPaid) {
                uint256 shortfall = c.assetsOwed - c.assetsPaid;
                uint256 consumed = shortfall < curatorBondValue ? shortfall : curatorBondValue;
                curatorBondValue -= consumed;
                uncoveredShortfall += consumed;
                emit ShortfallAbsorbed(curator, consumed, uncoveredShortfall);
            }
            _closeClaim(c);
        } else {
            c.status = uint8(SkylineTypes.ClaimStatus.PartiallySettled);
        }
    }

    /// @dev Burns the proportional share of a claim's reserved shares that `take` redeems.
    ///      A partial settlement leaves at least one share in the claim so its remaining
    ///      obligation can still be settled or restored on expiry.
    function _burnSettledShares(ClaimRecord storage c, uint128 take, uint128 remainingBefore) internal {
        if (take == 0 || remainingBefore == 0) return;

        uint256 shares = c.shares;
        if (shares == 0) return;

        uint256 burned;
        if (take >= remainingBefore) {
            burned = shares;
        } else {
            burned = (shares * uint256(take)) / uint256(remainingBefore);
            if (burned >= shares) burned = shares - 1;
        }

        if (burned == 0) return;

        c.shares = shares - burned;
        reservedShares[c.depositor] -= burned;
        totalSupply -= burned;
    }

    /// @dev Closes a claim, burning any shares still reserved for it.
    function _closeClaim(ClaimRecord storage c) internal {
        c.status = uint8(SkylineTypes.ClaimStatus.Settled);

        uint256 remaining = c.shares;
        if (remaining > 0) {
            c.shares = 0;
            reservedShares[c.depositor] -= remaining;
            totalSupply -= remaining;
        }

        if (openClaimCount > 0) openClaimCount--;
    }

    /// @notice Cancels an expired claim and restores the depositor's shares.
    /// @dev Permissionless after expiry. The depositor already had the full TTL to settle;
    ///      leaving an expired claim open would let a depositor grief the curator's capital
    ///      indefinitely. The shares always return to the depositor.
    /// @param claimId The claim to cancel.
    function cancelClaim(uint256 claimId) external nonReentrant {
        ClaimRecord storage c = claims[claimId];
        if (
            c.status != uint8(SkylineTypes.ClaimStatus.Registered)
                && c.status != uint8(SkylineTypes.ClaimStatus.PartiallySettled)
        ) {
            revert InvalidClaimStatus();
        }

        // The hook expires the claim and decrements its ledger.
        hook.expireClaim(poolId, claimId);

        balanceOf[c.depositor] += c.shares;
        reservedShares[c.depositor] -= c.shares;
        c.status = uint8(SkylineTypes.ClaimStatus.Expired);
        if (openClaimCount > 0) openClaimCount--;

        emit ClaimCancelled(c.depositor, claimId, c.shares);
    }

    /* -------------------------------------------------------------------------- */
    /*                                Curator exit                                */
    /* -------------------------------------------------------------------------- */

    /// @notice Requests the curator's exit.
    /// @dev The request is granted only when the hook's obligation ledger is empty. While claims
    ///      are outstanding the hook rejects the removal, regardless of what this contract says.
    function requestCuratorExit() external onlyCurator nonReentrant returns (bool) {
        if (lastCuratorExitRequest != 0 && block.timestamp < lastCuratorExitRequest + CURATOR_EXIT_COOLDOWN) {
            revert CoolingOff();
        }

        lastCuratorExitRequest = uint64(block.timestamp);
        curatorExitRequested = true;

        // Asks the hook. The hook's ledger is the binding constraint.
        hook.approveCuratorExit(poolId);

        emit CuratorExitRequested(curator, lastCuratorExitRequest);
        return true;
    }

    /// @notice Removes the curator's bonded liquidity and pays out the proceeds, netted by any
    ///         uncovered shortfall.
    /// @param liquidity The liquidity to remove.
    /// @return proceeds The net proceeds paid to the curator.
    function curatorExit(uint128 liquidity) external onlyCurator nonReentrant returns (uint256 proceeds) {
        if (!curatorExitRequested) revert CoolingOff();
        if (liquidity > curatorLiquidity) revert InsufficientAssets();

        uint128 liquidityBefore = curatorLiquidity;
        uint256 balanceBefore = asset.balanceOf(address(this));
        IERC20 other = IERC20(Currency.unwrap(_currency1()));
        uint256 otherBefore = other.balanceOf(address(this));

        // `_removeLiquidity` already updates the curator's liquidity counter.
        _removeLiquidity(SkylineTypes.CURATOR_SALT, liquidity, bytes(""));

        // The position returns both currencies. Convert the non-asset side before paying, or half
        // of the curator's bond is stranded in the vault as the wrong token.
        uint256 otherReceived = other.balanceOf(address(this)) - otherBefore;
        if (otherReceived > 0) _swapExactInput(otherReceived, false);

        uint256 gross = asset.balanceOf(address(this)) - balanceBefore;
        uint256 netted = gross < uncoveredShortfall ? gross : uncoveredShortfall;
        uncoveredShortfall -= netted;
        proceeds = gross - netted;

        // The bond's recorded value is a cost basis, not a live mark. Remove it in proportion to
        // the liquidity that left, so a full exit clears it and a partial exit keeps the
        // remaining basis. Reducing by `gross` would leave phantom bond value after a full exit.
        uint256 bondValue = curatorBondValue;
        curatorBondValue = liquidityBefore == 0 ? 0 : bondValue - (bondValue * liquidity) / liquidityBefore;

        asset.safeTransfer(msg.sender, proceeds);
        curatorExitRequested = false;

        emit CuratorExited(curator, proceeds, netted);
    }

    /* -------------------------------------------------------------------------- */
    /*                                Strategy                                    */
    /* -------------------------------------------------------------------------- */

    /// @notice Accrues the high-water-mark performance fee by minting dilution-only shares.
    /// @return feeShares The shares minted to the fee recipient.
    function accruePerformanceFee() external nonReentrant returns (uint256 feeShares) {
        if (totalSupply == 0) return 0;

        uint256 nav = _navPerShare();

        // A confirmed drawdown breach is DETECTED, not prevented. The penalty is economic:
        // the performance fee for this epoch is forfeited. The high-water mark ratchets to the
        // current NAV (it never falls), so the curator pays no fee on the loss and cannot
        // collect the fee they would otherwise have earned while in breach.
        if (hook.effectiveRiskState(poolId) >= uint8(SkylineTypes.RiskState.Breached)) {
            if (nav > highWaterMark) highWaterMark = nav;
            emit PerformanceFeeForfeited(highWaterMark, nav);
            return 0;
        }

        if (nav <= highWaterMark) return 0;

        uint256 profit = (nav - highWaterMark) * totalSupply;
        uint256 fee = (profit * perfFeeBps) / 10_000;
        if (fee == 0) return 0;

        feeShares = (fee * totalSupply) / nav;
        if (feeShares == 0) return 0;

        totalSupply += feeShares;
        balanceOf[feeRecipient] += feeShares;
        highWaterMark = nav;

        emit PerformanceFeeAccrued(feeShares, highWaterMark, nav);
    }

    /* -------------------------------------------------------------------------- */
    /*                              Pool interaction                              */
    /* -------------------------------------------------------------------------- */

    /// @dev Adds liquidity funded by a token0 deposit, swapping half of the deposit into the
    ///      pool's other currency so the position can be two-sided.
    /// @param salt The position salt.
    /// @param assets The token0 amount available.
    /// @return liquidity The liquidity added.
    function _addLiquidityFromAssets(bytes32 salt, uint256 assets) internal returns (uint128 liquidity) {
        if (assets == 0) return 0;

        IERC20 other = IERC20(Currency.unwrap(_currency1()));

        // Size the position against the WHOLE deposit before swapping. A concentrated position
        // does not want half of each currency: away from the range midpoint it wants more of one
        // side. Swapping a flat 50% leaves the excess stranded as idle balance, and idle balance
        // is not part of `totalAssets()`, so the depositor's NAV would silently drop.
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(poolId);
        (uint256 n0, uint256 n1) = _amountsForLiquidity(uint128(LIQUIDITY_UNIT));
        uint256 valuePerUnit = n0 + _toToken0(n1, sqrtPriceX96);
        if (valuePerUnit == 0) return 0;

        uint256 target = FullMath.mulDiv(assets, LIQUIDITY_UNIT, valuePerUnit);
        uint256 token0Needed = FullMath.mulDiv(target, n0, LIQUIDITY_UNIT);

        // Only swap the currency0 the position does not need.
        uint256 swapIn = assets > token0Needed ? assets - token0Needed : 0;
        uint256 before1 = other.balanceOf(address(this));
        if (swapIn > 0) _swapExactInput(swapIn);
        uint256 token1Held = other.balanceOf(address(this)) - before1;

        // Re-size against what is actually available: the swap moved the price.
        liquidity = _liquidityForDeposit(assets - swapIn, token1Held);
        if (liquidity == 0) return 0;

        return _addLiquidity(salt, liquidity);
    }

    /// @dev The liquidity obtainable from a token0 deposit, sized against what the vault can
    ///      actually pay for. Whichever side binds first wins.
    function _liquidityForDeposit(uint256 token0Budget, uint256 token1Held) internal view returns (uint128 liquidity) {
        (uint256 n0, uint256 n1) = _amountsForLiquidity(uint128(LIQUIDITY_UNIT));
        if (n0 == 0 || n1 == 0) return 0;

        uint256 l0 = FullMath.mulDiv(token0Budget, LIQUIDITY_UNIT, n0);
        uint256 l1 = FullMath.mulDiv(token1Held, LIQUIDITY_UNIT, n1);

        uint256 sized = l0 < l1 ? l0 : l1;
        return uint128((sized * LIQUIDITY_MARGIN_BPS) / 10_000);
    }

    /// @dev The token amounts the pool will charge for a liquidity amount at the current price.
    ///      Mirrors `Pool.modifyLiquidity` exactly.
    function _amountsForLiquidity(uint128 liquidity) internal view returns (uint256 amount0, uint256 amount1) {
        (uint160 sqrtPriceX96, int24 tick,,) = poolManager.getSlot0(poolId);
        uint160 sqrtLower = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 sqrtUpper = TickMath.getSqrtPriceAtTick(tickUpper);

        if (tick < tickLower) {
            amount0 = SqrtPriceMath.getAmount0Delta(sqrtLower, sqrtUpper, liquidity, true);
            amount1 = 0;
        } else if (tick < tickUpper) {
            amount0 = SqrtPriceMath.getAmount0Delta(sqrtPriceX96, sqrtUpper, liquidity, true);
            amount1 = SqrtPriceMath.getAmount1Delta(sqrtLower, sqrtPriceX96, liquidity, true);
        } else {
            amount0 = 0;
            amount1 = SqrtPriceMath.getAmount1Delta(sqrtLower, sqrtUpper, liquidity, true);
        }
    }

    /// @dev Adds liquidity to the pool under the given salt.
    function _addLiquidity(bytes32 salt, uint128 liquidity) internal returns (uint128 added) {
        if (liquidity == 0) return 0;

        CallbackData memory data = CallbackData({
            key: poolKey,
            action: Action.ModifyLiquidity,
            salt: salt,
            tickLower: tickLower,
            tickUpper: tickUpper,
            liquidityDelta: int256(uint256(liquidity)),
            zeroForOne: false,
            amountSpecified: 0,
            hookData: bytes("")
        });

        poolManager.unlock(abi.encode(data));

        if (salt == SkylineTypes.LP_SALT) {
            depositorLiquidity += liquidity;
        } else {
            curatorLiquidity += liquidity;
        }
        return liquidity;
    }

    /// @dev Removes liquidity from the pool under the given salt. The proceeds always land in
    ///      this contract; the caller decides where they go.
    /// @return amount The asset amount received.
    function _removeLiquidity(bytes32 salt, uint128 liquidity, bytes memory hookData)
        internal
        returns (uint256 amount)
    {
        if (liquidity == 0) return 0;

        CallbackData memory data = CallbackData({
            key: poolKey,
            action: Action.ModifyLiquidity,
            salt: salt,
            tickLower: tickLower,
            tickUpper: tickUpper,
            liquidityDelta: -int256(uint256(liquidity)),
            zeroForOne: false,
            amountSpecified: 0,
            hookData: hookData
        });

        uint256 balanceBefore = asset.balanceOf(address(this));
        poolManager.unlock(abi.encode(data));
        amount = asset.balanceOf(address(this)) - balanceBefore;

        if (salt == SkylineTypes.LP_SALT) {
            depositorLiquidity -= liquidity;
        } else {
            curatorLiquidity -= liquidity;
        }
    }

    /// @dev Swaps an exact amount of the vault's currency0 for the pool's other currency.
    function _swapExactInput(uint256 amountIn) internal {
        _swapExactInput(amountIn, true);
    }

    /// @dev Swaps an exact amount of one pool currency for the other.
    /// @param amountIn The exact input amount.
    /// @param zeroForOne True to sell currency0 for currency1.
    function _swapExactInput(uint256 amountIn, bool zeroForOne) internal {
        if (amountIn == 0) return;

        CallbackData memory data = CallbackData({
            key: poolKey,
            action: Action.Swap,
            salt: bytes32(0),
            tickLower: 0,
            tickUpper: 0,
            liquidityDelta: 0,
            zeroForOne: zeroForOne,
            amountSpecified: -int256(amountIn),
            hookData: bytes("")
        });

        poolManager.unlock(abi.encode(data));
    }

    /// @dev The pool's non-vault currency.
    function _currency1() internal view returns (Currency) {
        return poolKey.currency1;
    }

    /// @inheritdoc IUnlockCallback
    function unlockCallback(bytes calldata rawData) external returns (bytes memory) {
        if (msg.sender != address(poolManager)) revert NotCurator();

        CallbackData memory data = abi.decode(rawData, (CallbackData));

        BalanceDelta delta;
        if (data.action == Action.Swap) {
            // A NEGATIVE amountSpecified means EXACT INPUT: we sell exactly that much of the
            // input currency and receive whatever the output currency is worth.
            delta = poolManager.swap(
                data.key,
                IPoolManager.SwapParams({
                    zeroForOne: data.zeroForOne,
                    amountSpecified: data.amountSpecified,
                    // A zeroForOne swap walks the price DOWN, so its limit must be below the
                    // current price; the other direction walks it UP.
                    sqrtPriceLimitX96: data.zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
                }),
                data.hookData
            );
        } else {
            (delta,) = poolManager.modifyLiquidity(
                data.key,
                IPoolManager.ModifyLiquidityParams({
                    tickLower: data.tickLower,
                    tickUpper: data.tickUpper,
                    liquidityDelta: data.liquidityDelta,
                    salt: data.salt
                }),
                data.hookData
            );
        }

        _settleDelta(delta);
        return bytes("");
    }

    /// @dev Settles a balance delta against the PoolManager.
    ///
    ///      Sign convention (confirmed against Uniswap v4's own reference routers): a POSITIVE
    ///      delta means the vault RECEIVED tokens from the pool; a NEGATIVE delta means the vault
    ///      OWES the pool tokens.
    function _settleDelta(BalanceDelta delta) internal {
        Currency currency0 = poolKey.currency0;
        Currency currency1 = poolKey.currency1;

        int128 delta0 = delta.amount0();
        int128 delta1 = delta.amount1();

        // We owe the pool: sync the pool's balance, transfer in, then settle.
        if (delta0 < 0) _pay(currency0, uint128(uint128(-delta0)));
        if (delta1 < 0) _pay(currency1, uint128(uint128(-delta1)));

        // The pool owes us: take.
        if (delta0 > 0) poolManager.take(currency0, address(this), uint128(delta0));
        if (delta1 > 0) poolManager.take(currency1, address(this), uint128(delta1));
    }

    /// @dev Pays the PoolManager what it is owed.
    /// @dev The order matters: `sync` records the pool's balance BEFORE the transfer, and
    ///      `settle` credits the difference to the vault's transient delta.
    function _pay(Currency currency, uint128 amount) internal {
        if (currency.isAddressZero()) {
            poolManager.settle{value: amount}();
        } else {
            IERC20 token = IERC20(Currency.unwrap(currency));
            poolManager.sync(currency);
            token.safeTransfer(address(poolManager), amount);
            poolManager.settle();
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                              Views & accounting                            */
    /* -------------------------------------------------------------------------- */

    /// @notice Total depositor assets, excluding the curator bond.
    /// @dev The bond is the curator's capital, not a depositor claim. `totalAssets` must never
    ///      include it, or a depositor could redeem value the curator supplied.
    /// @inheritdoc ISkylineVault
    function totalAssets() public view returns (uint256) {
        return _assetsForLiquidity(depositorLiquidity);
    }

    /// @notice NAV per share, scaled by 1e18.
    function navPerShare() public view returns (uint256) {
        return _navPerShare();
    }

    function _navPerShare() internal view returns (uint256) {
        if (totalSupply == 0) return 1e18;
        return (totalAssets() * 1e18) / totalSupply;
    }

    /// @notice Converts assets to shares.
    function convertToShares(uint256 assets) public view returns (uint256) {
        uint256 supply = totalSupply;
        if (supply == 0) return assets;
        uint256 total = totalAssets();
        if (total == 0) return assets;
        return (assets * supply) / total;
    }

    /// @notice Converts shares to assets.
    function convertToAssets(uint256 shares) public view returns (uint256) {
        if (totalSupply == 0) return shares;
        uint256 total = totalAssets();
        if (total == 0) return shares;
        return (shares * total) / totalSupply;
    }

    /// @inheritdoc ISkylineVault
    function curatorBondValueFromPool() external view returns (uint256) {
        (uint128 liquidity,,) =
            poolManager.getPositionInfo(poolId, address(this), tickLower, tickUpper, SkylineTypes.CURATOR_SALT);
        return _assetsForLiquidity(liquidity);
    }

    /// @inheritdoc ISkylineVault
    function curatorExitProceeds() external view returns (uint256) {
        uint256 gross = curatorBondValue;
        return gross > uncoveredShortfall ? gross - uncoveredShortfall : 0;
    }

    /// @inheritdoc ISkylineVault
    function currentSkinBps() external view returns (uint32) {
        uint128 total = depositorLiquidity + curatorLiquidity;
        if (total == 0) return 0;
        return uint32((uint256(curatorLiquidity) * 10_000) / uint256(total));
    }

    /// @inheritdoc ISkylineVault
    function outstandingClaimLiquidity() external view returns (int128) {
        return hook.pendingLiquidity(poolId);
    }

    /// @inheritdoc ISkylineVault
    function outstandingClaims() external view returns (uint256) {
        return openClaimCount;
    }

    /// @notice The claim's TTL.
    function claimTtl() external view returns (uint32) {
        return _claimTtl();
    }

    function _claimTtl() internal view returns (uint32) {
        return hook.mandate(poolId).claimTtl;
    }

    /// @notice The vault's asset decimals.
    function assetDecimals() external view returns (uint8) {
        return IERC20MetadataView(address(asset)).decimals();
    }

    /* -------------------------------------------------------------------------- */
    /*                             Liquidity <-> assets                           */
    /* -------------------------------------------------------------------------- */

    /// @dev The liquidity a claim of `assets` is worth, sized against the currency0 side of the
    ///      position. Conservative: it never promises more than the position can deliver.
    function _liquidityForAssets(uint256 assets) internal view returns (uint128) {
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(poolId);
        (uint256 n0, uint256 n1) = _amountsForLiquidity(uint128(LIQUIDITY_UNIT));
        uint256 cost0 = n0 + _toToken0(n1, sqrtPriceX96);
        if (cost0 == 0) return 0;
        return uint128(FullMath.mulDiv(assets, LIQUIDITY_UNIT, cost0));
    }

    /// @dev The value of a liquidity amount in the vault's asset (currency0), at the pool's
    ///      current price. A position that straddles the price holds both currencies, so its
    ///      currency0 value is the currency0 side PLUS the currency0 value of the currency1 side.
    function _assetsForLiquidity(uint128 liquidity) internal view returns (uint256) {
        if (liquidity == 0) return 0;
        (uint160 sqrtPriceX96, int24 tick,,) = poolManager.getSlot0(poolId);
        uint160 sqrtLower = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 sqrtUpper = TickMath.getSqrtPriceAtTick(tickUpper);

        uint256 amount0;
        uint256 amount1;

        if (tick < tickLower) {
            amount0 = SqrtPriceMath.getAmount0Delta(sqrtLower, sqrtUpper, liquidity, true);
        } else if (tick < tickUpper) {
            amount0 = SqrtPriceMath.getAmount0Delta(sqrtPriceX96, sqrtUpper, liquidity, true);
            amount1 = SqrtPriceMath.getAmount1Delta(sqrtLower, sqrtPriceX96, liquidity, true);
        } else {
            amount1 = SqrtPriceMath.getAmount1Delta(sqrtLower, sqrtUpper, liquidity, true);
        }

        return amount0 + _toToken0(amount1, sqrtPriceX96);
    }

    /// @dev Converts a currency1 amount into its currency0 value at a given price.
    function _toToken0(uint256 amount1, uint160 sqrtPriceX96) internal pure returns (uint256) {
        if (amount1 == 0) return 0;
        uint256 q = 1 << 96;
        return FullMath.mulDiv(FullMath.mulDiv(amount1, q, sqrtPriceX96), q, sqrtPriceX96);
    }

    /// @dev Share preview for a deposit.
    ///      `totalAssets()` values the liquidity already deployed, and the incoming assets are
    ///      transferred *after* this call, so they must NOT be added to the denominator: doing so
    ///      prices the new depositor against their own capital and dilutes them.
    function _previewDeposit(uint256 assets) internal view returns (uint256) {
        uint256 supply = totalSupply;
        if (supply == 0) return assets;
        uint256 total = totalAssets();
        if (total == 0) return assets;
        return (assets * supply) / total;
    }

    /// @dev Conservative share preview for a redemption.
    function _previewRedeem(uint256 shares) internal view returns (uint256) {
        if (totalSupply == 0) return 0;
        uint256 total = totalAssets();
        if (total == 0) return 0;
        return (shares * total) / totalSupply;
    }

    /// @dev Opens the high-water mark if the NAV has risen.
    function _updateHwm() internal {
        uint256 nav = _navPerShare();
        if (nav > highWaterMark) highWaterMark = nav;
    }

    /// @dev The number of open claims belonging to an account.
    function _openClaimsOf(address account) internal view returns (uint256 count) {
        for (uint256 i = 0; i < nextClaimId; i++) {
            ClaimRecord storage c = claims[i];
            if (
                c.depositor == account
                    && (
                        c.status == uint8(SkylineTypes.ClaimStatus.Registered)
                            || c.status == uint8(SkylineTypes.ClaimStatus.PartiallySettled)
                    )
            ) {
                count++;
            }
        }
    }

    /// @dev The total outstanding obligation across all open claims, in liquidity units.
    function _totalOutstandingLiquidity() internal view returns (uint256 total) {
        for (uint256 i = 0; i < nextClaimId; i++) {
            ClaimRecord storage c = claims[i];
            if (
                c.status == uint8(SkylineTypes.ClaimStatus.Registered)
                    || c.status == uint8(SkylineTypes.ClaimStatus.PartiallySettled)
            ) {
                total += c.liquidityAmount - c.settledLiquidity;
            }
        }
    }
}

/// @dev Minimal metadata view, kept local to avoid an extra import in the vault's hot path.
interface IERC20MetadataView {
    function decimals() external view returns (uint8);
}
