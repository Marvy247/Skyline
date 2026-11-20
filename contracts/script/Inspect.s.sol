// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {SqrtPriceMath} from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";

import {SkylineTypes} from "../src/libraries/SkylineTypes.sol";

/// @notice Prints the live pool and vault state of a deployment. Read-only.
///   VAULT=0x.. HOOK=0x.. MANAGER=0x.. POOL_ID=0x.. \
///   forge script script/Inspect.s.sol:Inspect --rpc-url http://127.0.0.1:8545
contract Inspect is Script {
    using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;

    function run() external view {
        address vaultAddr = vm.envAddress("VAULT");
        address managerAddr = vm.envAddress("MANAGER");
        address hookAddr = vm.envAddress("HOOK");
        bytes32 poolIdRaw = vm.envBytes32("POOL_ID");
        PoolId poolId = PoolId.wrap(poolIdRaw);
        int24 lower = int24(vm.envOr("TICK_LOWER", int256(-60)));
        int24 upper = int24(vm.envOr("TICK_UPPER", int256(60)));

        IPoolManager manager = IPoolManager(managerAddr);

        (uint160 sqrtP, int24 tick, uint24 protocolFee, uint24 lpFee) = manager.getSlot0(poolId);
        console.log("sqrtPriceX96 :", sqrtP);
        console.log("tick         :", int256(tick));
        console.log("protocolFee  :", protocolFee);
        console.log("lpFee        :", lpFee);
        console.log("poolLiquidity:", manager.getLiquidity(poolId));

        _position(manager, poolId, vaultAddr, lower, upper, SkylineTypes.LP_SALT, "LP_SALT");
        _position(manager, poolId, vaultAddr, lower, upper, SkylineTypes.CURATOR_SALT, "CURATOR_SALT");

        (bool ok, bytes memory ret) = vaultAddr.staticcall(abi.encodeWithSignature("totalAssets()"));
        if (ok) console.log("totalAssets  :", abi.decode(ret, (uint256)));
        (ok, ret) = vaultAddr.staticcall(abi.encodeWithSignature("totalSupply()"));
        if (ok) console.log("totalSupply  :", abi.decode(ret, (uint256)));
        (ok, ret) = vaultAddr.staticcall(abi.encodeWithSignature("navPerShare()"));
        if (ok) console.log("navPerShare  :", abi.decode(ret, (uint256)));
        (ok, ret) = vaultAddr.staticcall(abi.encodeWithSignature("depositorLiquidity()"));
        if (ok) console.log("depositorLiq :", abi.decode(ret, (uint128)));
        (ok, ret) = vaultAddr.staticcall(abi.encodeWithSignature("curatorLiquidity()"));
        if (ok) console.log("curatorLiq   :", abi.decode(ret, (uint128)));

        (ok, ret) = hookAddr.staticcall(abi.encodeWithSignature("riskState(bytes32)", poolIdRaw));
        if (ok) console.log("riskState    :", abi.decode(ret, (uint8)));
        (ok, ret) = hookAddr.staticcall(abi.encodeWithSignature("effectiveRiskState(bytes32)", poolIdRaw));
        if (ok) console.log("effectiveRisk:", abi.decode(ret, (uint8)));
        (ok, ret) = hookAddr.staticcall(abi.encodeWithSignature("pendingLiquidity(bytes32)", poolIdRaw));
        if (ok) console.log("pendingLiq   :", abi.decode(ret, (int128)));
        (ok, ret) = hookAddr.staticcall(abi.encodeWithSignature("riskStateUpdatedAt(bytes32)", poolIdRaw));
        if (ok) console.log("riskUpdatedAt:", abi.decode(ret, (uint64)));
        (ok, ret) = hookAddr.staticcall(abi.encodeWithSignature("referencePrice(bytes32)", poolIdRaw));
        if (ok) console.log("referencePx  :", abi.decode(ret, (uint256)));
    }

    function _position(
        IPoolManager manager,
        PoolId poolId,
        address owner,
        int24 lower,
        int24 upper,
        bytes32 salt,
        string memory label
    ) internal view {
        (uint128 liquidity,,) = manager.getPositionInfo(poolId, owner, lower, upper, salt);
        (uint256 a0, uint256 a1) = _amounts(manager, poolId, lower, upper, liquidity);
        console.log(label);
        console.log("  liquidity :", liquidity);
        console.log("  amount0   :", a0);
        console.log("  amount1   :", a1);
        console.log("  value t0  :", a0 + a1);
    }

    function _amounts(IPoolManager manager, PoolId poolId, int24 lower, int24 upper, uint128 liquidity)
        internal
        view
        returns (uint256 amount0, uint256 amount1)
    {
        if (liquidity == 0) return (0, 0);
        (uint160 sqrtP, int24 tick,,) = manager.getSlot0(poolId);
        uint160 sqrtLower = TickMath.getSqrtPriceAtTick(lower);
        uint160 sqrtUpper = TickMath.getSqrtPriceAtTick(upper);

        if (tick < lower) {
            amount0 = SqrtPriceMath.getAmount0Delta(sqrtLower, sqrtUpper, liquidity, true);
        } else if (tick < upper) {
            amount0 = SqrtPriceMath.getAmount0Delta(sqrtP, sqrtUpper, liquidity, true);
            amount1 = SqrtPriceMath.getAmount1Delta(sqrtLower, sqrtP, liquidity, true);
        } else {
            amount1 = SqrtPriceMath.getAmount1Delta(sqrtLower, sqrtUpper, liquidity, true);
        }
    }
}
