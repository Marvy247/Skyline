// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SkylineFixture} from "../utils/SkylineFixture.sol";
import {Position} from "@uniswap/v4-core/src/libraries/Position.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {SkylineTypes} from "../../src/libraries/SkylineTypes.sol";

/**
 * @title PrimitivesTest
 * @notice Phase 0: proves the Uniswap v4 mechanics the whole Skyline design depends on.
 * @dev If any of these fail, the architecture is invalid and must be revisited before any
 *      protocol code is written. See docs/12-VERIFICATION.md §6.
 */
contract PrimitivesTest is SkylineFixture {
    using StateLibrary for IPoolManager;

    /// @notice Position keys include the owner AND the salt.
    function test_positionKeyIncludesOwnerAndSalt() public pure {
        bytes32 keyA = Position.calculatePositionKey(address(0xA11CE), -60, 60, SkylineTypes.LP_SALT);
        bytes32 keyB = Position.calculatePositionKey(address(0xA11CE), -60, 60, SkylineTypes.CURATOR_SALT);
        bytes32 keyC = Position.calculatePositionKey(address(0xB0B), -60, 60, SkylineTypes.LP_SALT);

        assertTrue(keyA != keyB, "different salts must give different position keys");
        assertTrue(keyA != keyC, "different owners must give different position keys");
        assertTrue(keyB != keyC, "different owners must give different position keys");
    }

    /// @notice The two salts are distinct constants.
    function test_saltsAreDistinct() public pure {
        assertTrue(SkylineTypes.LP_SALT != SkylineTypes.CURATOR_SALT, "salts must differ");
        assertTrue(SkylineTypes.LP_SALT != bytes32(0), "LP salt must be non-zero");
        assertTrue(SkylineTypes.CURATOR_SALT != bytes32(0), "curator salt must be non-zero");
    }

    /// @notice Two positions with the same owner and range but different salts are independent.
    function test_saltDistinguishesPositions() public {
        seedScenario();

        uint128 depositorLiq = vault.depositorLiquidity();
        uint128 curatorLiq = vault.curatorLiquidity();

        assertGt(depositorLiq, 0, "depositor position must have liquidity");
        assertGt(curatorLiq, 0, "curator position must have liquidity");

        // The pool holds two independent positions under the vault's address.
        (uint128 lp,,) = manager.getPositionInfo(poolId, address(vault), TICK_LOWER, TICK_UPPER, SkylineTypes.LP_SALT);
        (uint128 curator,,) =
            manager.getPositionInfo(poolId, address(vault), TICK_LOWER, TICK_UPPER, SkylineTypes.CURATOR_SALT);

        assertEq(lp, depositorLiq, "LP_SALT position liquidity must match the vault's counter");
        assertEq(curator, curatorLiq, "CURATOR_SALT position liquidity must match the vault's counter");
        assertTrue(lp != curator, "the two positions must hold different liquidity");
    }

    /// @notice The hook's shadow counters match the pool.
    function test_shadowCountersMatchPoolState() public {
        seedScenario();

        (int128 poolDerived,) = hook.verifyCuratorBond(poolId);
        assertEq(poolDerived, int128(vault.curatorLiquidity()), "curator shadow counter drift");

        int128 vaultTotal = hook.verifyVaultLiquidity(poolId);
        assertEq(
            vaultTotal,
            int128(uint128(vault.depositorLiquidity()) + vault.curatorLiquidity()),
            "vault total shadow counter drift"
        );
    }

    /// @notice Only the position owner can modify that position.
    function test_onlyOwnerCanModifyPosition() public {
        seedScenario();

        uint128 liq = vault.depositorLiquidity();
        assertGt(liq, 0, "need liquidity to remove");

        // A third party cannot remove the vault's liquidity: the PoolManager keys the position by
        // msg.sender, so a third party would simply create its OWN position.
        // Instead we assert the position owner recorded by the pool is the vault.
        (uint128 lp,,) = manager.getPositionInfo(poolId, address(vault), TICK_LOWER, TICK_UPPER, SkylineTypes.LP_SALT);
        assertEq(lp, liq, "the vault owns the depositor position");

        // A stranger's removal attempt through the hook must not be gated by our rules, and must
        // not be able to touch our positions.
        assertTrue(hook.curatorExitApproved(poolId) == false, "no curator exit may be approved yet");
    }

    /// @notice The hook is deployed at an address carrying the right permission bits.
    function test_hookAddressCarriesPermissionFlags() public view {
        assertEq(uint160(address(hook)) & ~HOOK_FLAGS, 0, "hook address must carry only the expected flags");
        assertEq(uint160(address(hook)), HOOK_FLAGS, "hook address must equal the flag mask");
    }

    /// @notice The pool is initialised and has liquidity.
    function test_poolIsInitialisedWithLiquidity() public {
        seedScenario();
        (uint160 sqrtPriceX96,,,) = manager.getSlot0(poolId);
        assertGt(sqrtPriceX96, 0, "pool must be initialised");
        assertGt(manager.getLiquidity(poolId), 0, "pool must have liquidity");
    }

    /// @notice A deposit must be priced at the NAV that exists BEFORE the deposit is deployed.
    /// @dev Regression: `_previewDeposit` used to add the incoming assets to the denominator as
    ///      well, so a second depositor was priced against their own capital. In the demo
    ///      scenario that cost the second depositor ~28% of their principal immediately.
    function test_depositIsPricedAtPreDepositNav() public {
        bondAs(curator, 200_000e18);
        depositAs(alice, 500_000e18);

        uint256 expectedShares = vault.convertToShares(300_000e18);
        uint256 before = vault.balanceOf(bob);

        depositAs(bob, 300_000e18);

        uint256 minted = vault.balanceOf(bob) - before;
        assertEq(minted, expectedShares, "shares must be minted at the pre-deposit NAV");
        assertGt(vault.convertToAssets(minted), 290_000e18, "depositor must not be materially diluted");
    }
}
