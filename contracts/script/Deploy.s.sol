// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {PoolModifyLiquidityTest} from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";

import {SkylineHook} from "../src/SkylineHook.sol";
import {SkylineKeeper} from "../src/SkylineKeeper.sol";
import {SkylineVault} from "../src/SkylineVault.sol";
import {SkylineTypes} from "../src/libraries/SkylineTypes.sol";
import {ISkylineHook} from "../src/interfaces/ISkylineHook.sol";
import {ISkylineVault} from "../src/interfaces/ISkylineVault.sol";

/**
 * @title DeploySkyline
 * @notice Deploys the full Skyline stack and, optionally, seeds the demo scenario.
 *
 * @dev Uniswap v4 decides which callbacks to invoke by inspecting the LOW 14 BITS of the hook
 *      address. `SkylineBaseHook` validates this in its constructor, so the hook must be
 *      deployed with CREATE2 at an address whose low 14 bits are EXACTLY the permission set.
 *      The mask is 0x3fff, so a valid salt is found in ~16k attempts, not 2^155.
 *
 *      Base Sepolia (recommended for the demo):
 *        export DEPLOYER_PRIVATE_KEY=0x...
 *        export BASE_SEPOLIA_RPC_URL=https://sepolia.base.org
 *        # Canonical v4 PoolManager is used automatically on chain 84532.
 *        # ORACLE defaults to the Base Sepolia ETH/USD feed when the pool is USDC/WETH.
 *        FOUNDRY_PROFILE=deploy forge script script/Deploy.s.sol:DeploySkyline \
 *          --rpc-url $BASE_SEPOLIA_RPC_URL --broadcast --verify
 *
 *      Base Sepolia with real USDC/WETH (currency0 = USDC, currency1 = WETH):
 *        ASSET=0x036CbD53842c5426634e7929541eC2318f3dCF7e \
 *        OTHER_TOKEN=0x4200000000000000000000000000000000000006 \
 *        SQRT_PRICE_X96=<sqrt(price) * 2^96> \
 *        BOOTSTRAP_LIQUIDITY=<liquidity units> \
 *        SEED_DEMO=true \
 *        FOUNDRY_PROFILE=deploy forge script script/Deploy.s.sol:DeploySkyline \
 *          --rpc-url $BASE_SEPOLIA_RPC_URL --broadcast --verify
 *
 *      Local (no token env, mints its own 18-decimal tokens, deploys its own PoolManager):
 *        DEPLOYER_PRIVATE_KEY=$ANVIL_KEY \
 *        FOUNDRY_PROFILE=deploy forge script script/Deploy.s.sol:DeploySkyline \
 *          --rpc-url http://127.0.0.1:8545 --broadcast --private-key $ANVIL_KEY
 *
 *      Environment:
 *        DEPLOYER_PRIVATE_KEY  required unless --private-key is passed
 *        ASSET                 the vault asset; must be the LOWER-addressed token.
 *                              Omit (together with OTHER_TOKEN) to deploy mock tokens locally.
 *        OTHER_TOKEN           the pool's other currency. Omit for local mock mode.
 *        POOL_MANAGER          existing v4 PoolManager. Defaults to the canonical Base Sepolia
 *                              manager on chain 84532; otherwise a fresh one is deployed.
 *        ORACLE                Chainlink-compatible feed. Defaults to Base Sepolia ETH/USD when
 *                              the pool is USDC/WETH on chain 84532. Set 0 to disable monitoring.
 *        CURATOR               curator of record (default: deployer)
 *        FEE_RECIPIENT         performance-fee recipient (default: deployer)
 *        SEED_DEMO             true to seed bootstrap liquidity + bond + two depositors
 *                              (default: true in local mode, false otherwise)
 *        DEPOSITOR_A/B         demo depositor addresses (default: deployer)
 *        SQRT_PRICE_X96        initial pool price (default: 2^96, a 1:1 pool)
 *        POOL_FEE              LP fee in hundredths of a bip (default: 3000 = 0.30%)
 *        POOL_TICK_SPACING     tick spacing (default: 60)
 *        TICK_LOWER/UPPER      vault position range. Defaults to +/-60 ticks around the
 *                              initial price, aligned to the tick spacing.
 *        BOOTSTRAP_*           third-party bootstrap position. In real-token mode,
 *                              BOOTSTRAP_LIQUIDITY must be set when SEED_DEMO=true.
 *        SEED_CURATOR_BOND     demo bond, in WHOLE asset units (default: 200,000 local / 20 real)
 *        SEED_DEPOSIT_A/B      demo deposits, in WHOLE asset units (default: 500,000/300,000 local,
 *                              50/30 real)
 *
 *      Note: the script can deploy its own PoolManager for a self-contained local demo, or bind
 *      to the canonical manager on Base Sepolia. The address it prints is the one the dashboard
 *      must use.
 */
contract DeploySkyline is Script {
    using PoolIdLibrary for PoolKey;

    /// @dev Low 14 bits of a v4 hook address carry the permission flags.
    uint160 internal constant HOOK_MASK = uint160((1 << 14) - 1);

    /// @dev Foundry broadcasts `new C{salt: ...}` through the deterministic deployment proxy,
    ///      so CREATE2 addresses are derived from THIS deployer, not the EOA. Predicting with
    ///      the EOA produces a salt whose on-chain address has the wrong flag bits.
    address internal constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    /// @dev The permission bits Skyline's hook needs. Must match `getHookPermissions()`.
    uint160 public constant HOOK_FLAGS = Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG
        | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG;

    /* ------------------------------ known networks ---------------------------- */

    uint256 internal constant BASE_SEPOLIA_CHAIN_ID = 84532;
    address internal constant BASE_SEPOLIA_POOL_MANAGER = 0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408;
    address internal constant BASE_SEPOLIA_ETH_USD = 0x4aDC67696bA383F43DD60A9e78F2C97Fbbfc7cb1;
    address internal constant BASE_SEPOLIA_USDC = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
    address internal constant BASE_SEPOLIA_WETH = 0x4200000000000000000000000000000000000006;

    /* ---------------------------- deployment state ---------------------------- */

    address public deployer;
    address public curator;
    address public feeRecipient;
    address public asset;
    address public otherToken;
    address public oracle;
    uint8 public assetDecimals;
    uint8 public otherDecimals;
    bool public localMode;
    bool public seeded;

    IPoolManager public manager;
    bool public canonicalManager;
    SkylineHook public hook;
    SkylineVault public vault;
    SkylineKeeper public keeper;
    PoolKey public key;

    int24 public tickLower;
    int24 public tickUpper;
    int24 public bootstrapTickLower;
    int24 public bootstrapTickUpper;
    uint128 public bootstrapLiquidity;

    function run() external {
        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        deployer = vm.addr(pk);

        curator = vm.envOr("CURATOR", deployer);
        feeRecipient = vm.envOr("FEE_RECIPIENT", deployer);

        address assetEnv = vm.envOr("ASSET", address(0));
        address otherEnv = vm.envOr("OTHER_TOKEN", address(0));
        localMode = assetEnv == address(0) && otherEnv == address(0);
        if (!localMode && (assetEnv == address(0) || otherEnv == address(0))) {
            revert("Deploy: set BOTH ASSET and OTHER_TOKEN, or neither for local mock mode");
        }
        seeded = vm.envOr("SEED_DEMO", localMode);

        vm.startBroadcast(pk);

        _resolveTokens(assetEnv, otherEnv);
        _resolveOracle();
        _deployCore();
        _registerPool();
        if (seeded) _seedDemo();
        _configureOracle();
        _deployKeeper();

        vm.stopBroadcast();

        _reportAndWrite();
    }

    /* -------------------------------------------------------------------------- */
    /*                                  Deploy                                    */
    /* -------------------------------------------------------------------------- */

    function _resolveTokens(address assetEnv, address otherEnv) internal {
        if (localMode) {
            MockERC20 a = new MockERC20("Skyline USD", "mUSD", 18);
            MockERC20 b = new MockERC20("Skyline ALT", "mALT", 18);
            // Mock tokens are interchangeable; the vault asset must be currency0.
            (asset, otherToken) = address(a) < address(b) ? (address(a), address(b)) : (address(b), address(a));
            assetDecimals = 18;
            otherDecimals = 18;
            return;
        }

        (asset, otherToken) = assetEnv < otherEnv ? (assetEnv, otherEnv) : (otherEnv, assetEnv);
        if (asset != assetEnv) {
            revert("Deploy: ASSET must be the lower-addressed token (v4 requires currency0 < currency1)");
        }
        assetDecimals = IERC20Metadata(asset).decimals();
        otherDecimals = IERC20Metadata(otherToken).decimals();
    }

    function _resolveOracle() internal {
        oracle = vm.envOr("ORACLE", address(0));

        // On Base Sepolia, a real USDC/WETH pool has an obvious external mark. Local mock pools
        // have no honest pair to point at, so they stay unmonitored unless ORACLE is set.
        if (
            oracle == address(0) && !localMode && block.chainid == BASE_SEPOLIA_CHAIN_ID && asset == BASE_SEPOLIA_USDC
                && otherToken == BASE_SEPOLIA_WETH
        ) {
            oracle = BASE_SEPOLIA_ETH_USD;
        }
    }

    function _deployCore() internal {
        _resolveManager();

        bytes32 salt = _mineSalt(manager, deployer);
        hook = new SkylineHook{salt: salt}(manager, deployer);

        _initializePool();
        _deployVault();
    }

    function _resolveManager() internal {
        address managerEnv = vm.envOr("POOL_MANAGER", address(0));
        if (managerEnv == address(0) && block.chainid == BASE_SEPOLIA_CHAIN_ID) {
            managerEnv = BASE_SEPOLIA_POOL_MANAGER;
        }

        if (managerEnv != address(0)) {
            manager = IPoolManager(managerEnv);
            canonicalManager = true;
        } else {
            manager = new PoolManager(deployer);
            canonicalManager = false;
        }
    }

    function _initializePool() internal {
        key = PoolKey({
            currency0: Currency.wrap(asset),
            currency1: Currency.wrap(otherToken),
            fee: uint24(vm.envOr("POOL_FEE", uint256(3000))),
            tickSpacing: int24(uint24(vm.envOr("POOL_TICK_SPACING", uint256(60)))),
            hooks: IHooks(address(hook))
        });

        uint160 sqrtPriceX96 = uint160(vm.envOr("SQRT_PRICE_X96", uint256(0)));
        if (sqrtPriceX96 == 0) {
            // A 1:1 default is only meaningful for the local mock pair. A real USDC/WETH pool
            // must be initialised at an actual price, or every subsequent deposit and range
            // calculation is nonsense.
            require(localMode, "Deploy: set SQRT_PRICE_X96 for real-token mode");
            sqrtPriceX96 = uint160(1 << 96);
        }
        manager.initialize(key, sqrtPriceX96);

        _resolveRanges(sqrtPriceX96, key.tickSpacing);
    }

    function _resolveRanges(uint160 sqrtPriceX96, int24 tickSpacing) internal {
        int24 currentTick = TickMath.getTickAtSqrtPrice(sqrtPriceX96);
        int24 halfWidth = int24(uint24(vm.envOr("RANGE_HALF_WIDTH_TICKS", uint256(60))));

        tickLower = _alignDown(currentTick - halfWidth, tickSpacing);
        tickUpper = _alignUp(currentTick + halfWidth, tickSpacing);
        tickLower = int24(vm.envOr("TICK_LOWER", int256(tickLower)));
        tickUpper = int24(vm.envOr("TICK_UPPER", int256(tickUpper)));
        require(tickLower < tickUpper, "Deploy: invalid tick range");
        require(
            tickLower % tickSpacing == 0 && tickUpper % tickSpacing == 0, "Deploy: range must align to tick spacing"
        );

        int24 bootstrapHalfWidth = int24(uint24(vm.envOr("BOOTSTRAP_HALF_WIDTH_TICKS", uint256(6000))));
        bootstrapTickLower = _alignDown(currentTick - bootstrapHalfWidth, tickSpacing);
        bootstrapTickUpper = _alignUp(currentTick + bootstrapHalfWidth, tickSpacing);
        bootstrapTickLower = int24(vm.envOr("BOOTSTRAP_TICK_LOWER", int256(bootstrapTickLower)));
        bootstrapTickUpper = int24(vm.envOr("BOOTSTRAP_TICK_UPPER", int256(bootstrapTickUpper)));

        if (localMode) {
            bootstrapLiquidity = uint128(vm.envOr("BOOTSTRAP_LIQUIDITY", uint256(1e30)));
        } else {
            bootstrapLiquidity = uint128(vm.envOr("BOOTSTRAP_LIQUIDITY", uint256(0)));
            if (seeded && bootstrapLiquidity == 0) {
                revert("Deploy: set BOOTSTRAP_LIQUIDITY for a real-token demo pool");
            }
        }
    }

    function _deployVault() internal {
        vault = new SkylineVault(
            IERC20(asset),
            manager,
            ISkylineHook(address(hook)),
            key,
            curator,
            feeRecipient,
            uint16(vm.envOr("PERF_FEE_BPS", uint256(1500))),
            tickLower,
            tickUpper
        );
    }

    function _registerPool() internal {
        // Register with no oracle first. This lets the demo seed liquidity even if the feed is
        // temporarily unavailable; `_configureOracle` wires and evaluates the feed afterwards.
        hook.registerPool(
            key.toId(),
            address(vault),
            curator,
            address(0),
            SkylineTypes.Mandate({
                maxFeeBps: uint24(vm.envOr("MAX_FEE_BPS", uint256(3000))),
                bandLower: tickLower - int24(uint24(vm.envOr("BAND_PADDING_TICKS", uint256(60)))),
                bandUpper: tickUpper + int24(uint24(vm.envOr("BAND_PADDING_TICKS", uint256(60)))),
                minSkinBps: uint32(vm.envOr("MIN_SKIN_BPS", uint256(1000))),
                maxDrawdownBps: uint32(vm.envOr("MAX_DRAWDOWN_BPS", uint256(1000))),
                claimTtl: uint32(vm.envOr("CLAIM_TTL", uint256(1 days))),
                riskState: uint8(SkylineTypes.RiskState.Normal)
            })
        );
    }

    function _configureOracle() internal {
        if (oracle == address(0)) return;

        hook.setOracle(key.toId(), oracle);
        // Establish the high-water mark immediately. If the feed is unavailable, the hook
        // degrades to `Restricted`, which freezes curator increases but not depositor exits.
        hook.updateRiskState(key.toId());
    }

    function _deployKeeper() internal {
        keeper = new SkylineKeeper(ISkylineHook(address(hook)), ISkylineVault(address(vault)), key.toId(), 10);
    }

    function _seedDemo() internal {
        // A fresh pool has zero liquidity: the first deposit would swap against nothing and
        // crash the price. Real pools are bootstrapped by their creator; the demo does the
        // same with a third-party position (salt 0), outside Skyline's two managed salts.
        PoolModifyLiquidityTest router = new PoolModifyLiquidityTest(manager);

        uint256 unit = 10 ** uint256(assetDecimals);

        if (localMode) {
            MockERC20(asset).mint(deployer, 10_000_000_000_000 * unit);
            MockERC20(otherToken).mint(deployer, 10_000_000_000_000 * unit);
        }

        IERC20(asset).approve(address(router), type(uint256).max);
        IERC20(otherToken).approve(address(router), type(uint256).max);

        router.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: bootstrapTickLower,
                tickUpper: bootstrapTickUpper,
                liquidityDelta: int256(uint256(bootstrapLiquidity)),
                salt: bytes32(0)
            }),
            ""
        );

        IERC20(asset).approve(address(vault), type(uint256).max);

        uint256 curatorBond = vm.envOr("SEED_CURATOR_BOND", localMode ? 200_000 * unit : 20 * unit);
        uint256 depositA = vm.envOr("SEED_DEPOSIT_A", localMode ? 500_000 * unit : 50 * unit);
        uint256 depositB = vm.envOr("SEED_DEPOSIT_B", localMode ? 300_000 * unit : 30 * unit);

        if (curator == deployer) {
            vault.curatorDeposit(curatorBond);
        } else {
            console.log("seed: CURATOR != deployer, skipping curator bond");
        }

        vault.deposit(depositA, vm.envOr("DEPOSITOR_A", deployer));
        vault.deposit(depositB, vm.envOr("DEPOSITOR_B", deployer));
    }

    /* -------------------------------------------------------------------------- */
    /*                                  Helpers                                   */
    /* -------------------------------------------------------------------------- */

    /// @dev Brute-forces a CREATE2 salt whose address has EXACTLY the permission flags in its low
    ///      14 bits. Expected work is 2^14 = 16,384 iterations; 2,000,000 leaves a wide margin.
    function _mineSalt(IPoolManager manager_, address hookOwner) internal pure returns (bytes32) {
        bytes32 initCodeHash =
            keccak256(abi.encodePacked(type(SkylineHook).creationCode, abi.encode(manager_, hookOwner)));

        for (uint256 i = 0; i < 2_000_000; i++) {
            bytes32 candidate = bytes32(i);
            address predicted = address(
                uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), CREATE2_DEPLOYER, candidate, initCodeHash))))
            );
            if ((uint160(predicted) & HOOK_MASK) == HOOK_FLAGS) return candidate;
        }

        revert("Deploy: no CREATE2 salt found");
    }

    function _alignDown(int24 tick, int24 spacing) internal pure returns (int24) {
        int24 compressed = tick / spacing;
        if (tick < 0 && tick % spacing != 0) compressed--;
        return compressed * spacing;
    }

    function _alignUp(int24 tick, int24 spacing) internal pure returns (int24) {
        int24 compressed = tick / spacing;
        if (tick > 0 && tick % spacing != 0) compressed++;
        return compressed * spacing;
    }

    function _reportAndWrite() internal {
        string memory obj = "mandate";
        vm.serializeUint(obj, "chainId", block.chainid);
        vm.serializeAddress(obj, "deployer", deployer);
        vm.serializeAddress(obj, "poolManager", address(manager));
        vm.serializeBool(obj, "canonicalPoolManager", canonicalManager);
        vm.serializeAddress(obj, "hook", address(hook));
        vm.serializeAddress(obj, "vault", address(vault));
        vm.serializeAddress(obj, "keeper", address(keeper));
        vm.serializeBytes32(obj, "poolId", PoolId.unwrap(key.toId()));
        vm.serializeAddress(obj, "currency0", Currency.unwrap(key.currency0));
        vm.serializeAddress(obj, "currency1", Currency.unwrap(key.currency1));
        vm.serializeUint(obj, "fee", uint256(key.fee));
        vm.serializeInt(obj, "tickSpacing", int256(key.tickSpacing));
        vm.serializeInt(obj, "tickLower", int256(tickLower));
        vm.serializeInt(obj, "tickUpper", int256(tickUpper));
        vm.serializeAddress(obj, "oracle", oracle);
        vm.serializeAddress(obj, "curator", curator);
        vm.serializeBool(obj, "mockTokens", localMode);
        string memory json = vm.serializeBool(obj, "seeded", seeded);

        string memory path = string.concat(vm.projectRoot(), "/deployments/", vm.toString(block.chainid), ".json");
        vm.writeFile(path, json);

        console.log("");
        console.log("---------------------------------------------");
        console.log("Skyline deployed");
        console.log("---------------------------------------------");
        console.log("Chain ID      :", block.chainid);
        console.log("PoolManager   :", address(manager));
        console.log("  canonical   :", canonicalManager);
        console.log("SkylineHook   :", address(hook));
        console.log("SkylineVault  :", address(vault));
        console.log("Keeper        :", address(keeper));
        console.log("PoolId        :", vm.toString(PoolId.unwrap(key.toId())));
        console.log("Currency0     :", Currency.unwrap(key.currency0));
        console.log("Currency1     :", Currency.unwrap(key.currency1));
        console.log("Tick range    :", vm.toString(int256(tickLower)), vm.toString(int256(tickUpper)));
        console.log("Oracle        :", oracle);
        console.log("Curator       :", curator);
        console.log("Seeded        :", seeded);
        console.log("---------------------------------------------");
        console.log("Dashboard env:");
        console.log("NEXT_PUBLIC_POOL_MANAGER=%s", vm.toString(address(manager)));
        console.log("NEXT_PUBLIC_HOOK_ADDRESS=%s", vm.toString(address(hook)));
        console.log("NEXT_PUBLIC_VAULT_ADDRESS=%s", vm.toString(address(vault)));
        console.log("NEXT_PUBLIC_POOL_ID=%s", vm.toString(PoolId.unwrap(key.toId())));
        console.log("Artifact      :", path);
    }
}
