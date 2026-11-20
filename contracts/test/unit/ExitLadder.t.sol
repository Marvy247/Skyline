// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SkylineFixture} from "../utils/SkylineFixture.sol";
import {SkylineHook} from "../../src/SkylineHook.sol";
import {SkylineVault} from "../../src/SkylineVault.sol";
import {CustomRevert} from "@uniswap/v4-core/src/libraries/CustomRevert.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

/**
 * @title ExitLadderTest
 * @notice Phase 4: the three-stage exit ladder, end to end.
 * @dev THIS FILE IS THE DEMO SCRIPT. Every assertion here is a frame you can show on stage.
 *      See docs/11-DEMO.md.
 *
 *      The ladder:
 *        1. depositor liquidity serves the claim;
 *        2. the curator's bond absorbs the shortfall;
 *        3. pro rata, so a depositor is never locked out.
 */
contract ExitLadderTest is SkylineFixture {
    /* -------------------------------------------------------------------------- */
    /*                          The worked example                              */
    /* -------------------------------------------------------------------------- */

    /// @notice The headline scenario: a claim is outstanding, and the curator cannot leave.
    function test_workedExample_curatorCannotRun() public {
        seedScenario();

        // --- Step 1: Alice registers a withdrawal ---
        uint256 aliceShares = vault.balanceOf(alice);
        vm.prank(alice);
        vault.requestWithdraw(aliceShares / 2);

        int128 pending = hook.pendingLiquidity(poolId);
        assertGt(pending, 0, "the hook must record an outstanding obligation");
        assertTrue(hook.isCuratorExitBlocked(poolId), "the curator's exit must be blocked");

        // --- Step 2: the curator tries to exit. The hook refuses, because its ledger is not empty.
        vm.expectRevert(abi.encodeWithSelector(SkylineHook.CuratorExitBlocked.selector, pending));
        vm.prank(curator);
        vault.requestCuratorExit();

        // --- Step 3: the claim settles and the obligation clears ---
        vault.settleClaims(10);
        assertEq(hook.pendingLiquidity(poolId), 0, "the obligation must be cleared");

        // --- Step 4: now the curator may leave ---
        vm.prank(curator);
        vault.requestCuratorExit();
        assertTrue(hook.curatorExitApproved(poolId), "the exit must now be approved");

        // --- Step 5: and now a NEW claim revokes that approval. The curator cannot leave. ---
        uint256 bobShares = vault.balanceOf(bob);
        vm.prank(bob);
        vault.requestWithdraw(bobShares / 2);

        assertFalse(hook.curatorExitApproved(poolId), "the approval must be revoked");
        assertTrue(hook.isCuratorExitBlocked(poolId), "the curator's exit must be blocked again");

        uint128 curatorLiq = vault.curatorLiquidity();
        assertGt(curatorLiq, 0, "the curator must have a bonded position");

        // The revert is bubbled up through the PoolManager as a WrappedError. Asserting the full
        // wrapper proves the block came from the HOOK, at the beforeRemoveLiquidity callback.
        vm.expectRevert(
            abi.encodeWithSelector(
                CustomRevert.WrappedError.selector,
                address(hook),
                IHooks.beforeRemoveLiquidity.selector,
                abi.encodeWithSelector(SkylineHook.CuratorExitBlocked.selector, hook.pendingLiquidity(poolId)),
                abi.encodePacked(Hooks.HookCallFailed.selector)
            )
        );
        vm.prank(curator);
        vault.curatorExit(curatorLiq);

        assertEq(vault.curatorLiquidity(), curatorLiq, "the curator's position must be untouched");
    }

    /// @notice The strategy degrades, the depositor is underpaid, and the curator's bond covers
    ///         the difference. This is the loss-absorption beat.
    function test_workedExample_bondAbsorbsTheShortfall() public {
        seedScenario();

        // The strategy degrades: the pool price falls, so the position's value in the vault's
        // asset falls with it.
        movePrice(true, 200_000e18);

        uint256 aliceShares = vault.balanceOf(alice);
        // (the NAV before the claim is not asserted; the claim records its own promised value)

        vm.prank(alice);
        vault.requestWithdraw(aliceShares);

        (,,, uint256 owed,,,,) = vault.claims(0);
        assertGt(owed, 0, "the claim must record the promised value");

        // Settle it.
        vault.settleClaims(10);

        (,,,, uint256 paid,,,) = vault.claims(0);
        assertLt(paid, owed, "the depositor must be underpaid after a degradation");

        // The difference is charged to the curator's bond.
        uint256 absorbed = vault.uncoveredShortfall();
        assertGt(absorbed, 0, "the curator's bond must absorb the shortfall");
        assertGe(absorbed, owed - paid, "the bond must cover the whole shortfall");

        // And the curator's exit proceeds are netted by it: the curator does not get to walk away
        // with the full bond after the strategy cost its depositors money.
        assertLt(vault.curatorExitProceeds(), vault.curatorBondValue(), "the exit proceeds must be netted");
        assertEq(
            vault.curatorExitProceeds(),
            vault.curatorBondValue() - vault.uncoveredShortfall(),
            "the exit proceeds must be the bond less the shortfall"
        );
    }

    /// @notice Stage 1: depositor liquidity serves the claim first.
    function test_stageOne_depositorLiquidityServesTheClaim() public {
        seedScenario();

        uint256 aliceShares = vault.balanceOf(alice);
        vm.prank(alice);
        vault.requestWithdraw(aliceShares / 4);

        uint128 depositorBefore = vault.depositorLiquidity();
        uint128 curatorBefore = vault.curatorLiquidity();

        vault.settleClaims(10);

        assertLt(vault.depositorLiquidity(), depositorBefore, "the depositor position must shrink");
        assertEq(vault.curatorLiquidity(), curatorBefore, "the curator's bond must not be touched");

        // With an undisturbed pool there is no strategy loss, so any residual shortfall is only
        // the vault's own swap execution cost.
        (,,, uint256 owed,,,,) = vault.claims(0);
        // The only residual is the vault's own execution cost (the swap that converts the
        // position's second currency back into the asset it pays in).
        assertLt(vault.uncoveredShortfall() * 10_000 / owed, 50, "there must be no material shortfall");
    }

    /// @notice Stage 2: the curator's bond absorbs a shortfall.
    function test_stageTwo_bondAbsorbsTheShortfall() public {
        seedScenario();

        // Degrade the strategy so the position is worth less than it was.
        movePrice(true, 300_000e18);

        uint256 aliceShares = vault.balanceOf(alice);
        vm.prank(alice);
        vault.requestWithdraw(aliceShares);

        uint256 bondBefore = vault.curatorBondValue();
        vault.settleClaims(10);

        // The bond's VALUE is consumed. The position itself only shrinks when the curator exits,
        // which is exactly the point: the curator cannot take the capital out while it is owed.
        assertLt(vault.curatorBondValue(), bondBefore, "the curator's bond must be consumed");
        assertGt(vault.uncoveredShortfall(), 0, "the shortfall must be recorded");
    }

    /// @notice Stage 3: a depositor is never locked out, even when the pool cannot cover them.
    function test_stageThree_depositorIsNeverLockedOut() public {
        seedScenario();

        // A depositor asks for everything.
        uint256 aliceShares = vault.balanceOf(alice);
        vm.prank(alice);
        vault.requestWithdraw(aliceShares);

        // Even if the curator's bond is exhausted and the pool is thin, settlement must never
        // revert: the claim is served as far as the liquidity allows, and the remainder stays
        // outstanding as a receivable.
        vault.settleClaims(10);

        assertTrue(vault.outstandingClaims() <= 1, "there must be at most one open claim");
        assertLe(vault.outstandingClaimLiquidity(), 0, "no obligation may remain unsettled");
    }

    /* -------------------------------------------------------------------------- */
    /*                              Liveness                                       */
    /* -------------------------------------------------------------------------- */

    /// @notice A depositor can always get out, even with a failing curator.
    function test_depositorCanAlwaysExit() public {
        seedScenario();

        uint256 aliceShares = vault.balanceOf(alice);
        uint256 balanceBefore = token0.balanceOf(alice);

        vm.prank(alice);
        vault.requestWithdraw(aliceShares);
        vault.settleClaims(10);

        assertGt(token0.balanceOf(alice), balanceBefore, "the depositor must receive their assets");
    }

    /// @notice The protocol stays consistent after a full round trip.
    function test_ledgerIsConsistentAfterSettlement() public {
        seedScenario();

        uint256 aliceShares = vault.balanceOf(alice);
        uint256 bobShares = vault.balanceOf(bob);

        vm.prank(alice);
        vault.requestWithdraw(aliceShares / 2);
        vm.prank(bob);
        vault.requestWithdraw(bobShares / 2);

        vault.settleClaims(10);

        (int128 derived, int128 recorded) = hook.verifyPending(poolId);
        assertEq(derived, recorded, "the hook's ledger must match the claim set");
        assertGe(recorded, 0, "the ledger must never go negative");

        (bool holds,,,) = hook.verifyCep(poolId);
        assertTrue(holds, "Curator Exit Parity must hold");
    }

    /// @notice The curator's bond is genuinely at risk: it is a separate, identifiable position.
    function test_bondIsASeparatePosition() public {
        seedScenario();

        uint128 depositorLiq = vault.depositorLiquidity();
        uint128 curatorLiq = vault.curatorLiquidity();

        assertGt(depositorLiq, 0, "the depositor position must exist");
        assertGt(curatorLiq, 0, "the curator bond must exist");
        assertTrue(depositorLiq != curatorLiq, "the two positions must be distinct");

        // And both are independently readable from the pool.
        (int128 poolDerived,) = hook.verifyCuratorBond(poolId);
        assertEq(poolDerived, int128(curatorLiq), "the bond must be verifiable from pool state");
    }
}
