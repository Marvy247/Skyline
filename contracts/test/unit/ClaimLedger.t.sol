// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SkylineFixture} from "../utils/SkylineFixture.sol";
import {SkylineHook} from "../../src/SkylineHook.sol";
import {SkylineVault} from "../../src/SkylineVault.sol";
import {SkylineTypes} from "../../src/libraries/SkylineTypes.sol";
import {CustomRevert} from "@uniswap/v4-core/src/libraries/CustomRevert.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

/**
 * @title ClaimLedgerTest
 * @notice Phase 2: the claim ledger, the authoritative obligation ledger, and the exit gate.
 * @dev These are the tests that decide whether Skyline is a real mechanism or a vault with a
 *      hook attached. See docs/05-SECURITY.md §4.
 *
 *      NOTE ON `vm.prank`: a prank applies to the NEXT call. Reading `vault.balanceOf(x)` inside
 *      the argument list consumes it, so every balance is read into a local first.
 */
contract ClaimLedgerTest is SkylineFixture {
    /// @dev A default mandate, used where the test needs to register a pool.
    function _mandate() internal pure returns (SkylineTypes.Mandate memory) {
        return SkylineTypes.Mandate({
            maxFeeBps: 3000,
            bandLower: -120,
            bandUpper: 120,
            minSkinBps: 1000,
            maxDrawdownBps: 1000,
            claimTtl: 1 days,
            riskState: 0
        });
    }

    /* -------------------------------------------------------------------------- */
    /*                            Registration & setup                           */
    /* -------------------------------------------------------------------------- */

    function test_poolIsRegistered() public view {
        SkylineTypes.PoolConfig memory config = hook.poolConfigs(poolId);
        assertTrue(config.registered, "pool must be registered");
        assertEq(config.vault, address(vault), "registered vault");
        assertEq(config.curator, curator, "registered curator");
    }

    function test_poolCannotBeRegisteredTwice() public {
        vm.expectRevert(SkylineHook.PoolAlreadyRegistered.selector);
        vm.prank(owner);
        hook.registerPool(poolId, address(vault), curator, address(0), _mandate());
    }

    function test_onlyOwnerCanRegisterPools() public {
        vm.expectRevert(SkylineHook.NotOwner.selector);
        hook.registerPool(poolId, address(vault), curator, address(0), _mandate());
    }

    /* -------------------------------------------------------------------------- */
    /*                              Claim registration                            */
    /* -------------------------------------------------------------------------- */

    function test_claimRegistrationRecordsAnObligation() public {
        seedScenario();

        uint256 shares = vault.balanceOf(alice);
        vm.prank(alice);
        uint256 claimId = vault.requestWithdraw(shares / 2);

        assertEq(claimId, 0, "first claim id");
        assertGt(hook.pendingLiquidity(poolId), 0, "the hook's ledger must record the obligation");
        assertTrue(hook.isCuratorExitBlocked(poolId), "the curator's exit must be blocked");
    }

    function test_onlyTheVaultCanRegisterClaims() public {
        seedScenario();

        vm.expectRevert(SkylineHook.NotVault.selector);
        hook.registerClaim(poolId, 0, 1e18, alice);
    }

    function test_claimIdsAreMonotonicAndNeverReused() public {
        seedScenario();

        uint256 aliceShares = vault.balanceOf(alice);
        uint256 bobShares = vault.balanceOf(bob);

        vm.prank(alice);
        uint256 first = vault.requestWithdraw(aliceShares / 4);
        vm.prank(bob);
        uint256 second = vault.requestWithdraw(bobShares / 4);

        assertEq(first, 0, "first id");
        assertEq(second, 1, "second id");
        assertEq(hook.nextClaimId(poolId), 2, "next id");
    }

    function test_ledgerMatchesTheClaimSet() public {
        seedScenario();

        uint256 aliceShares = vault.balanceOf(alice);
        uint256 bobShares = vault.balanceOf(bob);

        vm.prank(alice);
        vault.requestWithdraw(aliceShares / 4);
        vm.prank(bob);
        vault.requestWithdraw(bobShares / 4);

        (int128 derived, int128 recorded) = hook.verifyPending(poolId);
        assertEq(derived, recorded, "the hook's ledger must match the claim set");
        assertGt(recorded, 0, "there must be an outstanding obligation");
    }

    function test_pendingLedgerIsNeverNegative() public {
        seedScenario();

        uint256 aliceShares = vault.balanceOf(alice);
        uint256 bobShares = vault.balanceOf(bob);

        vm.prank(alice);
        vault.requestWithdraw(aliceShares);
        vm.prank(bob);
        vault.requestWithdraw(bobShares);

        assertGe(hook.pendingLiquidity(poolId), 0, "the ledger must never go negative");
    }

    function test_claimCannotBeRegisteredWithZeroLiquidity() public {
        seedScenario();

        uint256 nextId = hook.nextClaimId(poolId);
        vm.expectRevert(SkylineHook.ZeroAmount.selector);
        vm.prank(address(vault));
        hook.registerClaim(poolId, nextId, 0, alice);
    }

    /* -------------------------------------------------------------------------- */
    /*                             The curator exit gate                         */
    /* -------------------------------------------------------------------------- */

    function test_curatorExitRequestIsRefusedWhileObligationOutstanding() public {
        seedScenario();

        uint256 shares = vault.balanceOf(alice);
        vm.prank(alice);
        vault.requestWithdraw(shares / 2);

        int128 pending = hook.pendingLiquidity(poolId);
        assertGt(pending, 0, "there must be an outstanding obligation");

        // The hook refuses to even approve the exit.
        vm.expectRevert(abi.encodeWithSelector(SkylineHook.CuratorExitBlocked.selector, pending));
        vm.prank(curator);
        vault.requestCuratorExit();
    }

    function test_curatorRemovalIsBlockedEvenWhenTheExitWasApproved() public {
        seedScenario();

        // 1. No obligations: the curator's exit is approved.
        vm.prank(curator);
        vault.requestCuratorExit();
        assertTrue(hook.curatorExitApproved(poolId), "the exit must be approved");

        // 2. A depositor registers a claim. The approval is revoked.
        uint256 shares = vault.balanceOf(alice);
        vm.prank(alice);
        vault.requestWithdraw(shares / 2);
        assertFalse(hook.curatorExitApproved(poolId), "the approval must be revoked by a new claim");

        // 3. The curator tries to remove its bonded liquidity anyway. The HOOK rejects it, at the
        //    PoolManager, below the vault.
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
    }

    function test_curatorExitIsPermittedOnceObligationsAreSettled() public {
        seedScenario();

        uint256 shares = vault.balanceOf(alice);
        vm.prank(alice);
        vault.requestWithdraw(shares / 4);

        // Settle the claim, draining the obligation ledger.
        vm.warp(block.timestamp + 1 hours);
        vault.settleClaims(10);

        assertEq(hook.pendingLiquidity(poolId), 0, "the ledger must be empty");

        vm.prank(curator);
        vault.requestCuratorExit();
        assertTrue(hook.curatorExitApproved(poolId), "the exit must now be approved");

        uint128 curatorLiq = vault.curatorLiquidity();
        vm.prank(curator);
        vault.curatorExit(curatorLiq);

        assertEq(vault.curatorLiquidity(), 0, "the curator must have exited");
    }

    function test_approvalIsRevokedWhenANewObligationArrives() public {
        seedScenario();

        vm.prank(curator);
        vault.requestCuratorExit();
        assertTrue(hook.curatorExitApproved(poolId));

        uint256 shares = vault.balanceOf(alice);
        vm.prank(alice);
        vault.requestWithdraw(shares / 4);

        assertFalse(hook.curatorExitApproved(poolId), "the approval must be revoked");
    }

    /* -------------------------------------------------------------------------- */
    /*                              Claim expiry                                  */
    /* -------------------------------------------------------------------------- */

    function test_expiredClaimRestoresTheDepositorsShares() public {
        seedScenario();

        uint256 sharesBefore = vault.balanceOf(alice);
        vm.prank(alice);
        uint256 claimId = vault.requestWithdraw(sharesBefore / 2);

        assertEq(vault.balanceOf(alice), sharesBefore - sharesBefore / 2, "shares must be reserved");
        assertGt(hook.pendingLiquidity(poolId), 0, "the obligation must be outstanding");

        // Before the TTL, the claim cannot be cancelled.
        vm.expectRevert(SkylineHook.ClaimNotExpired.selector);
        vm.prank(alice);
        vault.cancelClaim(claimId);

        // After the TTL, it can.
        vm.warp(block.timestamp + 2 days);
        vm.prank(alice);
        vault.cancelClaim(claimId);

        assertEq(vault.balanceOf(alice), sharesBefore, "the shares must be restored");
        assertEq(hook.pendingLiquidity(poolId), 0, "the obligation must be released");
    }

    function test_expiredClaimReleasesTheCuratorLock() public {
        seedScenario();

        uint256 shares = vault.balanceOf(alice);
        vm.prank(alice);
        uint256 claimId = vault.requestWithdraw(shares / 2);
        assertTrue(hook.isCuratorExitBlocked(poolId));

        vm.warp(block.timestamp + 2 days);
        vm.prank(alice);
        vault.cancelClaim(claimId);

        assertFalse(hook.isCuratorExitBlocked(poolId), "the curator must be unlocked");
        assertEq(hook.pendingLiquidity(poolId), 0, "the obligation must be released");
    }

    /* -------------------------------------------------------------------------- */
    /*                              Claim limits                                  */
    /* -------------------------------------------------------------------------- */

    function test_openClaimLimitIsEnforced() public {
        seedScenario();

        uint256 shares = vault.balanceOf(alice) / 8;
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(alice);
            vault.requestWithdraw(shares);
        }

        vm.expectRevert(SkylineVault.ClaimLimitExceeded.selector);
        vm.prank(alice);
        vault.requestWithdraw(shares);
    }

    function test_cannotWithdrawMoreSharesThanOwned() public {
        seedScenario();

        uint256 shares = vault.balanceOf(alice);
        vm.expectRevert(SkylineVault.InsufficientShares.selector);
        vm.prank(alice);
        vault.requestWithdraw(shares + 1);
    }
}
