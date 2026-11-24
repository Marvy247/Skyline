// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title <Subject>Test
 * @notice Unit tests for <subject>.
 *
 * Conventions:
 *   - Name tests after the PROPERTY, not the function:
 *     test_curatorBlockedWhileObligationOutstanding  (good)
 *     test_beforeRemoveLiquidity_2                  (bad)
 *   - Assert the SPECIFIC custom error, not just "reverts".
 *   - A test that cannot fail is a comment. Delete it.
 */

import {Test} from "forge-std/Test.sol";

import {SkylineHook} from "../../src/SkylineHook.sol";
import {SkylineVault} from "../../src/SkylineVault.sol";

contract <Subject>Test is Test {
    SkylineHook internal hook;
    SkylineVault internal vault;

    address internal curator = makeAddr("curator");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    PoolId internal poolId;

    /* ------------------------------------------------------------------ */
    /*                              Setup                                 */
    /* ------------------------------------------------------------------ */

    function setUp() public {
        // --- deploy ---
        hook = new SkylineHook(address(this));
        vault = new SkylineVault(...);

        // --- register the pool (one-shot, before any liquidity) ---
        // poolId = ...;
        // hook.registerPool(poolId, address(vault), curator, address(0), mandate);

        // --- fund and seed ---
        // deal(address(asset), alice, 100_000e18);
        // vm.startPrank(alice);
        // vault.deposit(50_000e18, alice);
        // vm.stopPrank();
    }

    /* ------------------------------------------------------------------ */
    /*                            Happy path                              */
    /* ------------------------------------------------------------------ */

    function test_<property>() public {
        // Arrange
        // Act
        // Assert
    }

    /* ------------------------------------------------------------------ */
    /*                          Revert paths                             */
    /* ------------------------------------------------------------------ */

    function test_revertsWhen<Condition>() public {
        vm.expectRevert(SkylineHook.<Error>.selector);
        // ...
    }

    /// @dev Assert a custom error WITH its arguments.
    function test_revertsWith<Context>() public {
        vm.expectRevert(abi.encodeWithSelector(SkylineHook.<Error>.selector, 55_556));
        // ...
    }

    /* ------------------------------------------------------------------ */
    /*                              Fuzz                                  */
    /* ------------------------------------------------------------------ */

    function testFuzz_<property>(uint128 amount) public {
        amount = bound(amount, 1, type(uint128).max);
        // ...
    }

    function testFuzz_revertsWhenAmountExceedsBound(uint256 amount) public {
        amount = bound(amount, 1e30, type(uint256).max);
        vm.expectRevert(SkylineHook.<Error>.selector);
        // ...
    }

    /* ------------------------------------------------------------------ */
    /*                          The worked example                       */
    /* ------------------------------------------------------------------ */

    /// @notice Reproduces docs/04-ECONOMICS.md §5 exactly, number by number.
    ///         This test IS the demo's script.
    function test_workedExample() public {
        // Setup: C = 20_000, D = 80_000, V = 100_000

        // Step 1 — Alice registers a claim
        // Expect: pendingLiquidity == 55_556

        // Step 2 — the curator attempts to exit
        // Expect: revert CuratorExitBlocked(55_556)

        // Step 3 — settlement
        // Expect: pendingLiquidity == 0, Alice paid

        // Step 4 — the shortfall case
        // Expect: 10_000 supplied by the curator bond in the last-resort branch
    }
}
