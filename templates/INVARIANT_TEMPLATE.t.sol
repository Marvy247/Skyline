// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title <InvariantSuite>
 * @notice Stateful invariant tests for <subsystem>.
 *
 * The handler must generate ADVERSARIAL sequences, not merely random ones. A handler that
 * only exercises happy paths proves nothing.
 *
 * Run:
 *   forge test --match-path test/invariant/<Name>.t.sol --fuzz-runs 10000
 */

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {SkylineHook} from "../../src/SkylineHook.sol";
import {SkylineVault} from "../../src/SkylineVault.sol";

contract <Subsystem>Handler is Test {
    SkylineHook public hook;
    SkylineVault public vault;

    address[] public actors;

    /* ------------------------------------------------------------------ */
    /*                            Call selection                          */
    /* ------------------------------------------------------------------ */

    /// @dev Register a withdrawal claim.
    function registerClaim(uint128 liquidity, uint256 seed) external {
        uint256 claimId = hook.nextClaimId(poolId);
        vm.prank(address(vault));
        hook.registerClaim(poolId, claimId, liquidity, actors[seed % actors.length]);
    }

    /// @dev Settle a claim with an arbitrary amount — including too much, to test the bounds.
    function settleClaim(uint256 seed, uint128 amount) external {
        uint256 claimId = seed % hook.nextClaimId(poolId);
        vm.prank(address(vault));
        try hook.settleClaim(poolId, claimId, int128(amount)) {} catch {}
    }

    /// @dev Expire a claim once its TTL has passed.
    function expireClaim(uint256 seed) external {
        uint256 claimId = seed % hook.nextClaimId(poolId);
        hook.expireClaim(poolId, claimId);
    }

    /// @dev Try to approve a curator exit.
    function approveCuratorExit() external {
        vm.prank(address(vault));
        try hook.approveCuratorExit(poolId) {} catch {}
    }

    /// @dev Deposit.
    function deposit(uint256 assets, uint256 seed) external {
        vm.prank(actors[seed % actors.length]);
        try vault.deposit(assets, actors[seed % actors.length]) {} catch {}
    }

    /// @dev Request a withdrawal.
    function requestWithdraw(uint256 shares, uint256 seed) external {
        vm.prank(actors[seed % actors.length]);
        try vault.requestWithdraw(shares) {} catch {}
    }

    /// @dev Settle the queue.
    function settleClaims() external {
        try vault.settleClaims(10) {} catch {}
    }

    /// @dev THE ATTACK: attempt to remove curator liquidity while obligations are outstanding,
    ///      bypassing the vault's own logic and going straight to the PoolManager.
    function sneakyCuratorRemoval(int128 delta) external {
        vm.prank(address(vault));
        try vault.forceCuratorRemovalForTest(delta) {} catch {}
    }

    /* ------------------------------------------------------------------ */
    /*                             Modifiers                              */
    /* ------------------------------------------------------------------ */

    modifier onlyVault() {
        vm.startPrank(address(vault));
        _;
        vm.stopPrank();
    }
}

contract <InvariantSuite> is StdInvariant, Test {
    <Subsystem>Handler public handler;

    SkylineHook public hook;
    SkylineVault public vault;

    function setUp() public {
        // --- deploy ---
        hook = new SkylineHook(address(this));
        vault = new SkylineVault(...);

        // --- register ---
        // hook.registerPool(poolId, address(vault), curator, oracle, mandate);

        // --- actors ---
        handler = new <Subsystem>Handler();
        handler.hook = hook;
        handler.vault = vault;
        handler.actors.push(makeAddr("alice"));
        handler.actors.push(makeAddr("bob"));
        handler.actors.push(makeAddr("curator"));

        // --- target ---
        targetContract(address(handler));

        // --- selectors ---
        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = <Subsystem>Handler.registerClaim.selector;
        selectors[1] = <Subsystem>Handler.settleClaim.selector;
        selectors[2] = <Subsystem>Handler.expireClaim.selector;
        selectors[3] = <Subsystem>Handler.approveCuratorExit.selector;
        selectors[4] = <Subsystem>Handler.deposit.selector;
        selectors[5] = <Subsystem>Handler.requestWithdraw.selector;
        selectors[6] = <Subsystem>Handler.settleClaims.selector;
        selectors[7] = <Subsystem>Handler.sneakyCuratorRemoval.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetSelector(FuzzSelector({
            addr: address(handler),
            selectors: selectors,
            excludeContracts: [address(vault), address(hook)]
        }));
    }

    /* ------------------------------------------------------------------ */
    /*                             Invariants                             */
    /* ------------------------------------------------------------------ */

    /// @notice INV-2 — the ledger equals the sum of unsettled claim remainders, and is never
    ///         negative.
    function invariant_pendingMatchesClaims() public view {
        int128 derived;
        uint256 n = hook.nextClaimId(poolId);
        for (uint256 i = 0; i < n; i++) {
            <Claim> memory c = hook.claim(poolId, i);
            if (c.status == 1 || c.status == 4) {
                derived += int128(c.liquidityAmount - c.settledAmount);
            }
        }
        assertEq(hook.pendingLiquidity(poolId), derived, "pending != sum of claim remainders");
        assertGe(hook.pendingLiquidity(poolId), 0, "pending went negative");
    }

    /// @notice INV-3 — Curator Exit Parity. The curator's exit capacity never exceeds the
    ///         outstanding obligation.
    function invariant_cepHolds() public view {
        int128 q = hook.pendingLiquidity(poolId);
        int128 d = hook.depositorLiquidity(poolId);

        if (q > 0) {
            // The curator may only have exited under insolvency, and only by the shortfall.
            assertTrue(
                hook.curatorLiquidity(poolId) == 0 || d >= q || shortfallWasAbsorbed,
                "curator liquidity removed while obligations outstanding"
            );
        }

        (bool holds,,,) = hook.verifyCep(poolId);
        assertTrue(holds, "verifyCep reported a breach");
    }

    /// @notice INV-8 — approval is revoked whenever an obligation exists.
    function invariant_approvalRevokedWhenObligationExists() public view {
        if (hook.pendingLiquidity(poolId) > 0) {
            assertFalse(hook.curatorExitApproved(poolId), "approval survived an obligation");
        }
    }

    /// @notice INV-6 — no depositor lockout.
    function invariant_depositorNeverStuck() public view {
        assertTrue(
            vault.outstandingClaimLiquidity() == 0
                || vault.uncoveredShortfall() > 0
                || hook.depositorLiquidity(poolId) > 0,
            "no path to exit remains for a depositor"
        );
    }

    /// @notice INV-7 — the shadow counters match the pool's actual position liquidity.
    function invariant_shadowCountersMatchPool() public view {
        // Recompute from StateLibrary and compare with the hook's counters.
        // assertEq(hook.curatorLiquidity(poolId), poolDerivedCurator, "curator counter drift");
        // assertEq(hook.depositorLiquidity(poolId), poolDerivedDepositor, "depositor counter drift");
    }

    /// @dev Set when the handler observes the bond absorbing a shortfall.
    bool shortfallWasAbsorbed;

    /// @notice INV-11 — a claim cannot be settled twice for the same liquidity.
    function invariant_noDoubleSettlement() public view {
        uint256 n = hook.nextClaimId(poolId);
        for (uint256 i = 0; i < n; i++) {
            <Claim> memory c = hook.claim(poolId, i);
            assertLe(c.settledAmount, c.liquidityAmount, "claim over-settled");
        }
    }
}
