// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SkylineFixture} from "../utils/SkylineFixture.sol";
import {SkylineHook} from "../../src/SkylineHook.sol";

/**
 * @title ClaimAccountingTest
 * @notice The share side of the claim queue: reservation, settlement, expiry.
 * @dev These tests exist because the hook's liquidity ledger and the vault's share ledger are
 *      two different books. They must agree at every step, or a settled claim leaves phantom
 *      shares in `totalSupply` and dilutes everyone who stayed.
 */
contract ClaimAccountingTest is SkylineFixture {
    function _accountedSupply() internal view returns (uint256) {
        return vault.balanceOf(alice) + vault.balanceOf(bob) + vault.balanceOf(feeRecipient)
            + vault.reservedShares(alice) + vault.reservedShares(bob);
    }

    function test_reservedSharesAreStillPartOfSupply() public {
        seedScenario();

        assertEq(vault.totalSupply(), _accountedSupply(), "seed supply must reconcile");
        assertEq(vault.balanceOf(alice), 500_000e18, "alice shares");

        vm.prank(alice);
        vault.requestWithdraw(200_000e18);

        assertEq(vault.totalSupply(), _accountedSupply(), "reservation must not change supply");
        assertEq(vault.reservedShares(alice), 200_000e18, "shares are reserved");
        assertEq(vault.balanceOf(alice), 300_000e18, "shares leave the liquid balance");

        vault.settleClaims(10);

        assertEq(vault.totalSupply(), _accountedSupply(), "settled supply must reconcile");
        assertEq(vault.reservedShares(alice), 0, "reserved shares are burned");
    }

    function test_fullSettlementBurnsTheDepositorsShares() public {
        seedScenario();

        uint256 supplyBefore = vault.totalSupply();
        uint256 aliceShares = vault.balanceOf(alice);
        uint256 bobAssetsBefore = vault.convertToAssets(vault.balanceOf(bob));

        vm.prank(alice);
        vault.requestWithdraw(aliceShares);
        vault.settleClaims(10);

        assertEq(vault.totalSupply(), supplyBefore - aliceShares, "the claim's shares must be burned");
        assertEq(vault.balanceOf(alice), 0, "alice has no liquid shares left");
        assertEq(vault.reservedShares(alice), 0, "nothing remains reserved");
        assertEq(vault.outstandingClaims(), 0, "the claim is closed");
        assertEq(uint256(uint128(hook.pendingLiquidity(poolId))), 0, "the hook ledger is empty");

        uint256 bobAssetsAfter = vault.convertToAssets(vault.balanceOf(bob));
        assertGe(bobAssetsAfter, bobAssetsBefore * 999 / 1000, "the remaining depositor must not be diluted");
    }

    function test_fullSettlementAfterALossAlsoBurnsTheShares() public {
        seedScenario();
        movePrice(true, 200_000e18);

        uint256 supplyBefore = vault.totalSupply();
        uint256 aliceShares = vault.balanceOf(alice);

        vm.prank(alice);
        vault.requestWithdraw(aliceShares);
        vault.settleClaims(10);

        assertEq(vault.totalSupply(), supplyBefore - aliceShares, "loss settlement must burn too");
        assertEq(vault.outstandingClaims(), 0, "the claim must close after the depositor's liquidity serves it");
        assertEq(uint256(uint128(hook.pendingLiquidity(poolId))), 0, "the hook ledger must be empty");
        assertEq(vault.uncoveredShortfall(), 0, "a market loss is not charged to the bond");
    }

    function test_anyoneCanExpireAnExpiredClaim() public {
        seedScenario();

        uint256 aliceShares = vault.balanceOf(alice);
        vm.prank(alice);
        uint256 claimId = vault.requestWithdraw(aliceShares / 2);
        assertTrue(hook.isCuratorExitBlocked(poolId), "the claim must close the curator gate");

        // Permissionless, but never early.
        vm.expectRevert(SkylineHook.ClaimNotExpired.selector);
        vm.prank(bob);
        vault.cancelClaim(claimId);

        vm.warp(block.timestamp + 2 days);

        // Bob has no economic interest in the claim. He can still release the curator's capital;
        // the shares go back to Alice, not to him.
        vm.prank(bob);
        vault.cancelClaim(claimId);

        assertEq(vault.balanceOf(alice), aliceShares, "alice's shares must be restored in full");
        assertEq(vault.reservedShares(alice), 0, "nothing remains reserved");
        assertEq(vault.totalSupply(), _accountedSupply(), "expiry must not create or destroy shares");
        assertEq(vault.outstandingClaims(), 0, "the claim is closed");
        assertEq(uint256(uint128(hook.pendingLiquidity(poolId))), 0, "the hook ledger is empty");
        assertFalse(hook.isCuratorExitBlocked(poolId), "the curator must be unlocked");
    }
}
