// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SkylineFixture} from "../utils/SkylineFixture.sol";
import {SkylineHook} from "../../src/SkylineHook.sol";
import {console2} from "forge-std/console2.sol";

/**
 * @title CounterfactualTest
 * @notice The same vault, the same curator, the same withdrawal — with and without the gate.
 * @dev This is the "why the hook is load-bearing" file. The with-CEP path is the shipped
 *      behaviour; the without-CEP path is the ordering a plain ERC-4626 vault permits: the
 *      curator leaves first, and the depositor is served from whatever remains.
 *
 *      The assertion that matters is not the depositor's pennies. It is that in the without-CEP
 *      ordering the curator's bonded capital is already gone when the depositor's claim is
 *      registered, so there is nothing left to subordinate or slash. In the with-CEP ordering
 *      the curator is still in the pool, the exit is refused, and the bond is charged for the
 *      shortfall before the curator can leave.
 */
contract CounterfactualTest is SkylineFixture {
    /// @notice Without the gate: the curator exits, then the depositor withdraws.
    function test_withoutCep_curatorLeavesFirst() public {
        seedScenario();

        uint128 curatorLiq = vault.curatorLiquidity();
        assertGt(curatorLiq, 0, "the curator starts bonded");

        // A plain vault would let this through while a depositor is queued. Here the depositor
        // has not queued yet, so the exit is legitimate — the point is the ordering.
        vm.prank(curator);
        vault.requestCuratorExit();
        vm.prank(curator);
        vault.curatorExit(curatorLiq);

        assertEq(vault.curatorLiquidity(), 0, "the curator is gone before the depositor asks");
        assertEq(hook.curatorLiquidity(poolId), 0, "the hook saw the curator leave");
        assertEq(vault.curatorBondValue(), 0, "the bond accounting must be cleared on a full exit");
        assertEq(vault.curatorExitProceeds(), 0, "the curator cannot still appear bonded");

        uint256 aliceShares = vault.balanceOf(alice);
        vm.prank(alice);
        vault.requestWithdraw(aliceShares);

        assertEq(vault.curatorLiquidity(), 0, "no curator capital is left to back the claim");
        assertEq(vault.uncoveredShortfall(), 0, "there is no bond left to charge");

        vault.settleClaims(10);

        (,,,, uint256 paid,,,) = vault.claims(0);
        console2.log("without CEP: alice paid", paid);
        console2.log("without CEP: bond at claim time", uint256(0));
        console2.log("without CEP: shortfall", vault.uncoveredShortfall());
    }

    /// @notice With the gate: the depositor queues first, and the curator cannot leave.
    function test_withCep_curatorIsLockedUntilTheClaimSettles() public {
        seedScenario();

        uint128 curatorLiq = vault.curatorLiquidity();
        uint256 aliceShares = vault.balanceOf(alice);

        vm.prank(alice);
        uint256 claimId = vault.requestWithdraw(aliceShares);

        assertGt(vault.curatorLiquidity(), 0, "the bond is still in the pool when the claim exists");
        assertTrue(hook.isCuratorExitBlocked(poolId), "the hook must block the exit");

        // The exact revert the demo shows: the hook refuses, not the vault.
        vm.expectRevert(abi.encodeWithSelector(SkylineHook.CuratorExitBlocked.selector, hook.pendingLiquidity(poolId)));
        vm.prank(curator);
        vault.requestCuratorExit();

        // The claim is served while the curator is still there.
        vault.settleClaims(10);

        assertEq(vault.curatorLiquidity(), curatorLiq, "settlement must not silently move the bond");
        assertEq(hook.pendingLiquidity(poolId), 0, "the obligation is cleared");
        assertFalse(hook.isCuratorExitBlocked(poolId), "the gate reopens");

        (,,,, uint256 paid,,,) = vault.claims(claimId);
        console2.log("with CEP: alice paid", paid);
        console2.log("with CEP: bond after settlement", vault.curatorBondValue());
        console2.log("with CEP: shortfall", vault.uncoveredShortfall());

        // Now the curator may ask again. The contrast is the ordering, not a guarantee that a
        // market loss is fully insured: the bond is slashed by the shortfall and netted from the
        // curator's proceeds. It is never allowed to leave before the claim is served.
        vm.prank(curator);
        vault.requestCuratorExit();
        assertTrue(hook.curatorExitApproved(poolId), "the exit is approved only after the queue is clear");
    }
}
