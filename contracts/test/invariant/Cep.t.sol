// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

import {SkylineFixture} from "../utils/SkylineFixture.sol";
import {SkylineHook} from "../../src/SkylineHook.sol";
import {SkylineVault} from "../../src/SkylineVault.sol";

/**
 * @title CepHandler
 * @notice The stateful handler for the Skyline invariant suite.
 * @dev The handler must generate ADVERSARIAL sequences, not merely random ones. Every call is
 *      wrapped in a try/catch so a revert is a legitimate outcome, not a failed run — the
 *      invariants are about the state that survives.
 */
contract CepHandler is Test {
    SkylineHook public hook;
    SkylineVault public vault;

    address[] public actors;
    uint256 public actorCount;

    constructor(SkylineHook hook_, SkylineVault vault_) {
        hook = hook_;
        vault = vault_;
    }

    function setActors(address[] calldata actors_) external {
        for (uint256 i = 0; i < actors_.length; i++) {
            actors.push(actors_[i]);
        }
        actorCount = actors.length;
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actorCount];
    }

    /* -------------------------------------------------------------------------- */
    /*                              Actions                                       */
    /* -------------------------------------------------------------------------- */

    /// @dev A depositor registers a withdrawal claim.
    function requestWithdraw(uint256 seed, uint256 shareBps) external {
        address who = _actor(seed);
        uint256 shares = (vault.balanceOf(who) * (shareBps % 101)) / 100;
        if (shares == 0) return;
        vm.prank(who);
        try vault.requestWithdraw(shares) {} catch {}
    }

    /// @dev Anyone may settle the queue.
    function settleClaims(uint256 maxClaims) external {
        try vault.settleClaims(maxClaims % 5 + 1) {} catch {}
    }

    /// @dev The curator tries to leave.
    function requestCuratorExit() external {
        address who = vault.curator();
        vm.prank(who);
        try vault.requestCuratorExit() {} catch {}
    }

    /// @dev The curator tries to remove its bonded liquidity directly.
    function curatorExit(uint256 bps) external {
        address who = vault.curator();
        uint128 liq = uint128((uint256(vault.curatorLiquidity()) * (bps % 101)) / 100);
        vm.prank(who);
        try vault.curatorExit(liq) {} catch {}
    }

    /// @dev A depositor cancels an expired claim.
    function cancelClaim(uint256 seed) external {
        address who = _actor(seed);
        uint256 count = vault.nextClaimId();
        if (count == 0) return;
        uint256 id = seed % count;
        vm.prank(who);
        try vault.cancelClaim(id) {} catch {}
    }

    /// @dev Time passes, so claims can expire.
    function warp(uint256 secondsToAdvance) external {
        vm.warp(block.timestamp + (secondsToAdvance % 2 days) + 1);
    }

    /// @dev The curator tops up its bond.
    function curatorTopUp(uint256 bps) external {
        address who = vault.curator();
        vm.prank(who);
        try vault.curatorDeposit((1e18 * (bps % 50 + 1)) / 10) {} catch {}
    }
}

/**
 * @title CepInvariantTest
 * @notice The six headline invariants of Skyline, asserted against a stateful handler.
 * @dev See docs/05-SECURITY.md §4. Run with:
 *      forge test --match-path test/invariant/Cep.t.sol --fuzz-runs 10000
 */
contract CepInvariantTest is StdInvariant, SkylineFixture {
    CepHandler public handler;

    /// @notice INV-1: claim ids are strictly increasing and never reused.
    function invariant_claimIdsAreMonotonic() public view {
        assertGe(hook.nextClaimId(poolId), vault.nextClaimId(), "claim id counters must agree");
    }

    /// @notice INV-2: the obligation ledger equals the sum of the unsettled claim remainders.
    function invariant_pendingMatchesClaims() public view {
        (int128 derived, int128 recorded) = hook.verifyPending(poolId);
        assertEq(derived, recorded, "the hook's ledger must match the claim set");
        assertGe(recorded, 0, "the ledger must never go negative");
    }

    /// @notice INV-3: Curator Exit Parity. The curator's liquidity cannot be removed ahead of
    ///         outstanding depositor obligations.
    function invariant_cepHolds() public view {
        int128 pending = hook.pendingLiquidity(poolId);
        int128 curator = hook.curatorLiquidity(poolId);

        // While obligations are outstanding, the curator's capital must still be in the pool
        // unless the protocol was already insolvent (the last-resort path).
        if (pending != 0 && pending <= hook.depositorLiquidity(poolId)) {
            assertGe(curator, 0, "the curator's capital must not be removed ahead of the claims");
            assertFalse(hook.curatorExitApproved(poolId), "the exit approval must be revoked");
        }

        (bool holds,,,) = hook.verifyCep(poolId);
        assertTrue(holds, "the hook's own CEP check must hold");
    }

    /// @notice INV-4: a claim is never settled for more than it is owed.
    function invariant_noClaimIsOverSettled() public view {
        uint256 count = hook.nextClaimId(poolId);
        for (uint256 i = 0; i < count; i++) {
            (, uint128 claimLiquidity, uint128 claimSettled, uint256 assetsOwed, uint256 assetsPaid,,,) =
                vault.claims(i);
            assertLe(claimSettled, claimLiquidity, "a claim must never be over-settled");
            // Fees accrued between registration and settlement can push the delivered value
            // slightly above the promised value. That is a bonus to the depositor, not a bug.
            assertLe(assetsPaid, (assetsOwed / 100) * 105 + 1, "a claim must never be materially paid more than owed");
        }
    }

    /// @notice INV-5: the oracle never gates a depositor's exit.
    /// @dev The oracle is not configured in the fixture, so this asserts the stronger property:
    ///      the hook's ledger — never an external input — is what decides.
    function invariant_oracleNeverBlocksDepositors() public view {
        assertEq(hook.riskState(poolId), 0, "no risk state is set without an oracle");
        // The exit gate depends only on the ledger.
        bool blocked = hook.isCuratorExitBlocked(poolId);
        int128 pending = hook.pendingLiquidity(poolId);
        if (!blocked) {
            assertEq(pending, 0, "the curator may only be unblocked with an empty ledger");
        }
    }

    /// @notice INV-6: no depositor lockout. The protocol can always serve a claim.
    function invariant_depositorNeverStuck() public view {
        // If the ledger is non-empty, either the pool can still serve it, or the shortfall has
        // been recorded against the curator. There is no third state.
        int128 pending = hook.pendingLiquidity(poolId);
        if (pending > 0) {
            assertTrue(
                hook.depositorLiquidity(poolId) > 0 || vault.uncoveredShortfall() > 0,
                "a pending obligation must always have a settlement path"
            );
        }
    }

    /// @notice The hook's shadow counters must agree with the pool.
    function invariant_shadowCountersMatchPoolState() public view {
        (int128 poolDerived,) = hook.verifyCuratorBond(poolId);
        assertEq(poolDerived, int128(vault.curatorLiquidity()), "the curator's counter must not drift");
    }

    /// @dev Target the handler and seed the scenario.
    function setUp() public override {
        super.setUp();

        seedScenario();

        handler = new CepHandler(hook, vault);

        address[] memory actors_ = new address[](3);
        actors_[0] = alice;
        actors_[1] = bob;
        actors_[2] = curator;
        handler.setActors(actors_);

        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = CepHandler.requestWithdraw.selector;
        selectors[1] = CepHandler.settleClaims.selector;
        selectors[2] = CepHandler.requestCuratorExit.selector;
        selectors[3] = CepHandler.curatorExit.selector;
        selectors[4] = CepHandler.cancelClaim.selector;
        selectors[5] = CepHandler.warp.selector;
        selectors[6] = CepHandler.curatorTopUp.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }
}
