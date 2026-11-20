// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {PoolModifyLiquidityTest} from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {SortTokens} from "@uniswap/v4-core/test/utils/SortTokens.sol";

import {SkylineHook} from "../../src/SkylineHook.sol";
import {SkylineBaseHook} from "../../src/SkylineBaseHook.sol";
import {SkylineVault} from "../../src/SkylineVault.sol";
import {DeployableSkylineHook} from "./DeployableSkylineHook.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SkylineTypes} from "../../src/libraries/SkylineTypes.sol";

/**
 * @title SkylineFixture
 * @notice Deploys a complete Skyline system for tests: PoolManager, tokens, hook, pool, vault.
 * @dev The hook is deployed at an address whose low bits encode the permission flags Uniswap v4
 *      requires. The implementation is deployed normally and its bytecode is etched onto the
 *      flag-correct address, which is the standard v4 testing pattern.
 */
contract SkylineFixture is Test {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using LPFeeLibrary for uint24;

    IPoolManager public manager;
    PoolSwapTest public swapRouter;
    PoolModifyLiquidityTest public modifyLiquidityRouter;

    MockERC20 public token0;
    MockERC20 public token1;

    SkylineHook public hook;
    SkylineVault public vault;

    PoolKey public key;
    PoolId public poolId;

    address public owner = makeAddr("owner");
    address public curator = makeAddr("curator");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public feeRecipient = makeAddr("feeRecipient");

    uint160 public constant SQRT_PRICE_1_1 = 79228162514264337593543950336; // 2**96
    int24 public constant TICK_LOWER = -60;
    int24 public constant TICK_UPPER = 60;
    uint24 public constant LP_FEE = 3000;
    /// @dev The depth of the pool's bootstrap position.
    uint128 public constant BOOTSTRAP_LIQUIDITY = 1e29;

    /// @dev The permission bits Skyline's hook needs.
    uint160 public constant HOOK_FLAGS = Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG
        | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG;

    function setUp() public virtual {
        // --- PoolManager and routers ---
        manager = new PoolManager(address(this));
        swapRouter = new PoolSwapTest(manager);
        modifyLiquidityRouter = new PoolModifyLiquidityTest(manager);

        // --- Tokens ---
        token0 = new MockERC20("USD0", "USD0", 18);
        token1 = new MockERC20("USD1", "USD1", 18);
        (Currency c0, Currency c1) = SortTokens.sort(token0, token1);

        // --- Hook, etched onto a permission-correct address ---
        DeployableSkylineHook impl = new DeployableSkylineHook(manager, owner);
        address hookAddr = address(uint160(HOOK_FLAGS));
        vm.etch(hookAddr, address(impl).code);
        hook = SkylineHook(hookAddr);

        // --- Pool ---
        key = PoolKey({currency0: c0, currency1: c1, fee: LP_FEE, tickSpacing: 60, hooks: IHooks(hookAddr)});
        poolId = key.toId();
        manager.initialize(key, SQRT_PRICE_1_1);

        // --- Vault ---
        vault = new SkylineVault(
            IERC20(Currency.unwrap(c0)),
            manager,
            hook,
            key,
            curator,
            feeRecipient,
            1500, // 15% performance fee
            TICK_LOWER,
            TICK_UPPER
        );

        // --- Register the pool with the hook (one-shot, before any liquidity) ---
        SkylineTypes.Mandate memory m = SkylineTypes.Mandate({
            maxFeeBps: 3000,
            bandLower: TICK_LOWER - 60,
            bandUpper: TICK_UPPER + 60,
            minSkinBps: 1000,
            maxDrawdownBps: 1000,
            claimTtl: 1 days,
            riskState: uint8(SkylineTypes.RiskState.Normal)
        });
        vm.prank(owner);
        hook.registerPool(poolId, address(vault), curator, address(0), m);

        // --- Fund the actors ---
        _fund(alice, 1_000_000e18);
        _fund(bob, 1_000_000e18);
        _fund(curator, 1_000_000e18);
        _fund(address(this), 1e32);

        token0.approve(address(vault), type(uint256).max);
        token1.approve(address(vault), type(uint256).max);

        // The v4 test routers settle by pulling tokens from the caller, and the ROUTER is the
        // spender, so the routers need an allowance from this test contract.
        token0.approve(address(swapRouter), type(uint256).max);
        token1.approve(address(swapRouter), type(uint256).max);
        token0.approve(address(modifyLiquidityRouter), type(uint256).max);
        token1.approve(address(modifyLiquidityRouter), type(uint256).max);

        // --- Bootstrap the pool ---
        // A fresh pool has no liquidity, so the first swap would crash the price to the limit.
        // Real pools are seeded by their creator; Skyline does the same. The bootstrap position
        // is a third party (salt 0) and is deliberately outside Skyline's two managed positions.
        _bootstrapPool();
    }

    /// @dev Seeds the pool with a deep third-party position so swaps inside the vault's deposit
    ///      path do not move the price materially.
    function _bootstrapPool() internal {
        token0.approve(address(modifyLiquidityRouter), type(uint256).max);
        token1.approve(address(modifyLiquidityRouter), type(uint256).max);

        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: TICK_LOWER,
                tickUpper: TICK_UPPER,
                liquidityDelta: int256(uint256(BOOTSTRAP_LIQUIDITY)),
                salt: bytes32(0)
            }),
            ""
        );
    }

    function _fund(address who, uint256 amount) internal {
        token0.mint(who, amount);
        token1.mint(who, amount);
        vm.prank(who);
        token0.approve(address(vault), type(uint256).max);
        vm.prank(who);
        token1.approve(address(vault), type(uint256).max);
    }

    /* -------------------------------------------------------------------------- */
    /*                                Helpers                                     */
    /* -------------------------------------------------------------------------- */

    /// @dev Deposits for an actor.
    function depositAs(address who, uint256 assets) internal {
        vm.prank(who);
        vault.deposit(assets, who);
    }

    /// @dev Bonds capital for the curator.
    function bondAs(address who, uint256 assets) internal {
        vm.prank(who);
        vault.curatorDeposit(assets);
    }

    /// @dev Seeds the canonical scenario: curator bond + two depositors.
    function seedScenario() internal {
        bondAs(curator, 200_000e18);
        depositAs(alice, 500_000e18);
        depositAs(bob, 300_000e18);
    }

    /// @dev Moves the pool price by a percentage, to simulate strategy degradation.
    function movePrice(bool zeroForOne, uint256 amountIn) internal {
        swapRouter.swap(
            key,
            IPoolManager.SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: -int256(amountIn),
                sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ""
        );
    }
}
