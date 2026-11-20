// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SkylineFixture} from "./utils/SkylineFixture.sol";
import {MockChainlinkFeed} from "./utils/MockChainlinkFeed.sol";
import {SkylineHook} from "../src/SkylineHook.sol";
import {SkylineKeeper} from "../src/SkylineKeeper.sol";
import {SkylineVault} from "../src/SkylineVault.sol";
import {ISkylineHook} from "../src/interfaces/ISkylineHook.sol";
import {ISkylineVault} from "../src/interfaces/ISkylineVault.sol";
import {SkylineTypes} from "../src/libraries/SkylineTypes.sol";

/**
 * @title OracleTest
 * @notice Phase 7: the Chainlink risk regime.
 *
 * @dev The assertions that matter:
 *   1. Every oracle failure mode escalates the risk state and NEVER reverts the hook.
 *   2. `Restricted` freezes risk-INCREASING curator operations only.
 *   3. A depositor can always request and settle a withdrawal, in every risk state, with the
 *      oracle returning zero, negative, stale, incomplete or reverting data. INV-5 is fuzzed.
 *   4. A stale risk evaluation is treated as `Restricted` for the curator, so the keeper is an
 *      optimisation, not a dependency.
 */
contract OracleTest is SkylineFixture {
    MockChainlinkFeed internal feed;

    /// @dev A plausible ETH/USD answer with Chainlink's usual 8 decimals.
    uint256 internal constant MARK = 2000e8;

    function setUp() public virtual override {
        super.setUp();

        feed = new MockChainlinkFeed();
        feed.setAnswer(int256(MARK), block.timestamp);

        vm.prank(owner);
        hook.setOracle(poolId, address(feed));

        // Establish the high-water mark. Without this, an oracle-configured pool is treated as
        // "unknown" and curator actions are restricted until the first evaluation.
        hook.updateRiskState(poolId);
    }

    /* -------------------------------------------------------------------------- */
    /*                          The happy path and HWM                            */
    /* -------------------------------------------------------------------------- */

    function test_healthyMarkStaysNormal() public {
        assertEq(hook.updateRiskState(poolId), uint8(SkylineTypes.RiskState.Normal));
        assertEq(hook.referencePrice(poolId), MARK);
        assertEq(hook.effectiveRiskState(poolId), uint8(SkylineTypes.RiskState.Normal));
    }

    function test_referenceIsAHighWaterMarkNotTheFirstPrice() public {
        feed.setAnswer(int256(MARK * 15 / 10), block.timestamp); // 3000
        assertEq(hook.updateRiskState(poolId), uint8(SkylineTypes.RiskState.Normal));
        assertEq(hook.referencePrice(poolId), MARK * 15 / 10);

        feed.setAnswer(int256(MARK * 14 / 10), block.timestamp); // 2800: 6.67% down from 3000
        assertEq(hook.updateRiskState(poolId), uint8(SkylineTypes.RiskState.Normal));

        feed.setAnswer(int256(MARK * 135 / 100), block.timestamp); // 2700: 10% down from 3000
        assertEq(hook.updateRiskState(poolId), uint8(SkylineTypes.RiskState.Restricted));

        feed.setAnswer(int256(MARK * 15 / 10), block.timestamp); // recovery
        assertEq(hook.updateRiskState(poolId), uint8(SkylineTypes.RiskState.Normal));
    }

    function test_drawdownEscalatesToRestrictedThenConfirmedBreached() public {
        feed.setAnswer(int256((MARK * 90) / 100), block.timestamp); // 10%
        assertEq(hook.updateRiskState(poolId), uint8(SkylineTypes.RiskState.Restricted));

        // A single 20% print freezes the curator but does not expose the bond.
        feed.setAnswer(int256((MARK * 80) / 100), block.timestamp);
        assertEq(hook.updateRiskState(poolId), uint8(SkylineTypes.RiskState.Restricted));
        assertEq(hook.breachObservations(poolId), 1);

        // The second consecutive confirmation is a breach.
        assertEq(hook.updateRiskState(poolId), uint8(SkylineTypes.RiskState.Breached));
        assertEq(hook.breachObservations(poolId), 2);
    }

    function test_aSingleExtremePrintCannotBreach() public {
        feed.setAnswer(int256((MARK * 50) / 100), block.timestamp); // 50% in one print
        assertEq(hook.updateRiskState(poolId), uint8(SkylineTypes.RiskState.Restricted));
        assertEq(hook.breachObservations(poolId), 1);

        // Recovery before confirmation resets the counter and returns to Normal.
        feed.setAnswer(int256(MARK), block.timestamp);
        assertEq(hook.updateRiskState(poolId), uint8(SkylineTypes.RiskState.Normal));
        assertEq(hook.breachObservations(poolId), 0);
    }

    /* -------------------------------------------------------------------------- */
    /*                            Oracle failure modes                            */
    /* -------------------------------------------------------------------------- */

    function test_zeroAnswerEscalatesWithoutReverting() public {
        feed.setAnswer(0, block.timestamp);
        assertEq(hook.updateRiskState(poolId), uint8(SkylineTypes.RiskState.Restricted));
        assertEq(hook.effectiveRiskState(poolId), uint8(SkylineTypes.RiskState.Restricted));
    }

    function test_negativeAnswerEscalatesWithoutReverting() public {
        feed.setAnswer(-1, block.timestamp);
        assertEq(hook.updateRiskState(poolId), uint8(SkylineTypes.RiskState.Restricted));
    }

    function test_staleAnswerEscalatesWithoutReverting() public {
        uint256 staleAt = block.timestamp > 2 hours ? block.timestamp - 2 hours : 0;
        feed.setAnswer(int256(MARK), staleAt);
        assertEq(hook.updateRiskState(poolId), uint8(SkylineTypes.RiskState.Restricted));
    }

    function test_revertingFeedEscalatesWithoutReverting() public {
        feed.setRevert(true);
        assertEq(hook.updateRiskState(poolId), uint8(SkylineTypes.RiskState.Restricted));
    }

    function test_incompleteRoundEscalatesWithoutReverting() public {
        // `answeredInRound < roundId` means the current round has not been answered.
        feed.setRaw(10, int256(MARK), block.timestamp, 9);
        assertEq(hook.updateRiskState(poolId), uint8(SkylineTypes.RiskState.Restricted));
    }

    function test_failureNeverRelaxesAnExistingBreach() public {
        feed.setAnswer(int256((MARK * 80) / 100), block.timestamp);
        hook.updateRiskState(poolId);
        hook.updateRiskState(poolId);
        assertEq(hook.riskState(poolId), uint8(SkylineTypes.RiskState.Breached));

        feed.setRevert(true);
        assertEq(hook.updateRiskState(poolId), uint8(SkylineTypes.RiskState.Breached));
    }

    function test_oracleUnsetLeavesTheStoredStateAlone() public {
        vm.prank(owner);
        hook.setOracle(poolId, address(0));

        assertEq(hook.updateRiskState(poolId), uint8(SkylineTypes.RiskState.Normal));
        assertEq(hook.effectiveRiskState(poolId), uint8(SkylineTypes.RiskState.Normal));

        // With no monitor configured, the curator can still operate.
        bondAs(curator, 10_000e18);
        assertGt(vault.curatorLiquidity(), 0);
    }

    /* -------------------------------------------------------------------------- */
    /*                    Restricted freezes the curator, not LPs                 */
    /* -------------------------------------------------------------------------- */

    function test_restrictedBlocksCuratorAddsButNotDepositorAdds() public {
        seedScenario();

        feed.setAnswer(int256((MARK * 85) / 100), block.timestamp); // 15% drawdown
        assertEq(hook.updateRiskState(poolId), uint8(SkylineTypes.RiskState.Restricted));

        // The curator cannot increase exposure.
        vm.prank(curator);
        vm.expectRevert(SkylineVault.RiskStateRestricted.selector);
        vault.curatorDeposit(10_000e18);

        // The hook itself would also reject the callback, so the block does not depend on the
        // vault's courtesy check.
        vm.prank(curator);
        vm.expectRevert(SkylineVault.RiskStateRestricted.selector);
        vault.performRebalance(TICK_LOWER - 60, TICK_UPPER + 60, 1);

        // A depositor can still enter. The risk regime is not a depositor gate.
        depositAs(alice, 10_000e18);
    }

    function test_staleEvaluationRestrictsTheCuratorButNotDepositorExits() public {
        seedScenario();

        // The stored state is Normal, but the evaluation is now older than the freshness window.
        vm.warp(block.timestamp + 2 hours);
        assertEq(hook.riskState(poolId), uint8(SkylineTypes.RiskState.Normal));
        assertEq(hook.effectiveRiskState(poolId), uint8(SkylineTypes.RiskState.Restricted));

        vm.prank(curator);
        vm.expectRevert(SkylineVault.RiskStateRestricted.selector);
        vault.curatorDeposit(10_000e18);

        // A depositor's exit still works end-to-end without any keeper or oracle refresh.
        uint256 shares = vault.balanceOf(alice);
        vm.prank(alice);
        uint256 claimId = vault.requestWithdraw(shares / 2);
        vault.settleClaims(10);

        SkylineTypes.Claim memory c = hook.claim(poolId, claimId);
        assertEq(c.status, uint8(SkylineTypes.ClaimStatus.Settled));
        assertEq(c.settledAmount, c.liquidityAmount);
    }

    function test_breachedBlocksCuratorAddsAndForfeitsTheFee() public {
        seedScenario();

        feed.setAnswer(int256((MARK * 80) / 100), block.timestamp);
        hook.updateRiskState(poolId);
        assertEq(hook.updateRiskState(poolId), uint8(SkylineTypes.RiskState.Breached));

        vm.prank(curator);
        vm.expectRevert(SkylineVault.RiskStateRestricted.selector);
        vault.curatorDeposit(10_000e18);

        uint256 hwmBefore = vault.highWaterMark();
        assertEq(vault.accruePerformanceFee(), 0);
        assertGe(vault.highWaterMark(), hwmBefore, "the high-water mark must never fall");
    }

    function test_depositorExitWorksInEveryRiskState() public {
        seedScenario();

        uint8[3] memory states = [
            uint8(SkylineTypes.RiskState.Normal),
            uint8(SkylineTypes.RiskState.Restricted),
            uint8(SkylineTypes.RiskState.Breached)
        ];

        for (uint256 i = 0; i < states.length; i++) {
            if (states[i] == uint8(SkylineTypes.RiskState.Restricted)) {
                feed.setAnswer(int256((MARK * 85) / 100), block.timestamp);
            } else if (states[i] == uint8(SkylineTypes.RiskState.Breached)) {
                feed.setAnswer(int256((MARK * 80) / 100), block.timestamp);
                hook.updateRiskState(poolId);
            } else {
                feed.setAnswer(int256(MARK), block.timestamp);
            }
            assertEq(hook.updateRiskState(poolId), states[i]);

            uint256 shares = vault.balanceOf(bob);
            vm.prank(bob);
            uint256 claimId = vault.requestWithdraw(shares / 4);
            vault.settleClaims(10);

            SkylineTypes.Claim memory c = hook.claim(poolId, claimId);
            assertEq(c.status, uint8(SkylineTypes.ClaimStatus.Settled));
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                                  INV-5                                     */
    /* -------------------------------------------------------------------------- */

    /// @notice Fuzz every oracle failure and assert that a depositor can still exit.
    function testFuzz_oracleNeverBlocksDepositorExit(int256 answer, uint256 staleness, bool revertFeed) public {
        seedScenario();

        answer = bound(answer, -1e30, 1e30);
        staleness = bound(staleness, 0, 3 hours);
        uint256 feedUpdatedAt = block.timestamp > staleness ? block.timestamp - staleness : 0;

        feed.setAnswer(answer, feedUpdatedAt);
        feed.setRevert(revertFeed);

        // The hook must not revert, whatever the feed does.
        hook.updateRiskState(poolId);

        uint256 shares = vault.balanceOf(alice);
        vm.prank(alice);
        uint256 claimId = vault.requestWithdraw(shares / 2);

        assertEq(uint256(hook.claim(poolId, claimId).status), uint8(SkylineTypes.ClaimStatus.Registered));

        // Settlement is permissionless and independent of the oracle.
        vault.settleClaims(10);

        uint8 status = hook.claim(poolId, claimId).status;
        assertTrue(
            status == uint8(SkylineTypes.ClaimStatus.Settled)
                || status == uint8(SkylineTypes.ClaimStatus.PartiallySettled),
            "a depositor claim must make progress in every risk state"
        );
    }
}

/**
 * @title OracleBootstrapTest
 * @notice A pool with an oracle configured but never evaluated is UNKNOWN, not safe.
 */
contract OracleBootstrapTest is SkylineFixture {
    function test_oracleConfiguredButNeverEvaluatedRestrictsOnlyTheCurator() public {
        MockChainlinkFeed feed = new MockChainlinkFeed();
        feed.setAnswer(2000e8, block.timestamp);

        vm.prank(owner);
        hook.setOracle(poolId, address(feed));

        assertEq(hook.riskStateUpdatedAt(poolId), 0);
        assertEq(hook.effectiveRiskState(poolId), uint8(SkylineTypes.RiskState.Restricted));

        vm.prank(curator);
        vm.expectRevert(SkylineVault.RiskStateRestricted.selector);
        vault.curatorDeposit(10_000e18);

        // The first evaluation establishes the reference and opens the regime.
        assertEq(hook.updateRiskState(poolId), uint8(SkylineTypes.RiskState.Normal));
        assertEq(hook.effectiveRiskState(poolId), uint8(SkylineTypes.RiskState.Normal));

        bondAs(curator, 10_000e18);
        assertGt(vault.curatorLiquidity(), 0);
    }
}

/**
 * @title KeeperTest
 * @notice Chainlink Automation refreshes the regime and serves claims. It is optional.
 */
contract KeeperTest is SkylineFixture {
    MockChainlinkFeed internal feed;
    SkylineKeeper internal keeper;

    function setUp() public override {
        super.setUp();

        feed = new MockChainlinkFeed();
        feed.setAnswer(2000e8, block.timestamp);
        vm.prank(owner);
        hook.setOracle(poolId, address(feed));
        hook.updateRiskState(poolId);

        keeper = new SkylineKeeper(ISkylineHook(address(hook)), ISkylineVault(address(vault)), poolId, 10);
    }

    function test_checkUpkeepIsFalseWhenNothingIsDue() public view {
        (bool needed,) = keeper.checkUpkeep("");
        assertFalse(needed);
    }

    function test_checkUpkeepIsTrueWhenTheRiskEvaluationIsStale() public {
        vm.warp(block.timestamp + 2 hours);
        (bool needed,) = keeper.checkUpkeep("");
        assertTrue(needed);
    }

    function test_performUpkeepRefreshesRiskAndSettlesClaims() public {
        seedScenario();

        uint256 shares = vault.balanceOf(alice);
        vm.prank(alice);
        uint256 claimId = vault.requestWithdraw(shares / 2);

        vm.warp(block.timestamp + 2 hours);
        feed.setAnswer(2000e8, block.timestamp);

        (bool needed, bytes memory performData) = keeper.checkUpkeep("");
        assertTrue(needed);

        keeper.performUpkeep(performData);

        assertEq(hook.riskStateUpdatedAt(poolId), uint64(block.timestamp));
        assertEq(hook.effectiveRiskState(poolId), uint8(SkylineTypes.RiskState.Normal));
        assertEq(hook.claim(poolId, claimId).status, uint8(SkylineTypes.ClaimStatus.Settled));
    }

    function test_keeperIsNeverRequiredForADepositorExit() public {
        seedScenario();

        vm.warp(block.timestamp + 2 hours);
        // Deliberately do NOT run the keeper and do NOT refresh the oracle.
        uint256 shares = vault.balanceOf(bob);
        vm.prank(bob);
        vault.requestWithdraw(shares / 2);
        vault.settleClaims(10);

        assertEq(hook.pendingLiquidity(poolId), 0);
    }
}
