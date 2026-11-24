// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SkylineFixture} from "../utils/SkylineFixture.sol";
import {MockChainlinkFeed} from "../utils/MockChainlinkFeed.sol";
import {SkylineHook} from "../../src/SkylineHook.sol";
import {SkylineVault} from "../../src/SkylineVault.sol";
import {ISkylineHook} from "../../src/interfaces/ISkylineHook.sol";
import {SkylineTypes} from "../../src/libraries/SkylineTypes.sol";

/**
 * @title PerformanceFeeTest
 * @notice The performance-fee surface: dilution-only minting on profit, forfeiture on a
 *         confirmed drawdown breach, and the high-water mark that never falls.
 */
contract PerformanceFeeTest is SkylineFixture {
    MockChainlinkFeed internal feed;

    uint256 internal constant MARK = 2000e8;

    function setUp() public override {
        super.setUp();

        feed = new MockChainlinkFeed();
        feed.setAnswer(int256(MARK), block.timestamp);

        vm.prank(owner);
        hook.setOracle(poolId, address(feed));
        hook.updateRiskState(poolId);
    }

    function test_zeroSupplyReturnsZero() public {
        assertEq(vault.accruePerformanceFee(), 0);
    }

    function test_noFeeWhenNavDoesNotExceedHwm() public {
        seedScenario();

        // The high-water mark was raised to the seed NAV. Nothing has happened since, so the
        // NAV is at (or below) the mark and no fee is due.
        uint256 hwmBefore = vault.highWaterMark();
        uint256 supplyBefore = vault.totalSupply();
        uint256 feeRecipientBefore = vault.balanceOf(feeRecipient);

        assertEq(vault.accruePerformanceFee(), 0);
        assertEq(vault.highWaterMark(), hwmBefore, "HWM must not move when no profit");
        assertEq(vault.totalSupply(), supplyBefore, "no dilution when no fee");
        assertEq(vault.balanceOf(feeRecipient), feeRecipientBefore, "fee recipient unchanged");
    }

    function test_feeAccruesAndMintsDilutionOnlyShares() public {
        seedScenario();

        // Lower the high-water mark by 1% so the next accrual sees a realistic profit. This is a
        // test-only shortcut; in production the mark only ever rises from real NAV.
        uint256 navBefore = vault.navPerShare();
        vm.store(address(vault), bytes32(uint256(8)), bytes32((navBefore * 99) / 100));

        uint256 supplyBefore = vault.totalSupply();
        uint256 feeRecipientBefore = vault.balanceOf(feeRecipient);
        uint256 assetBalanceBefore = vault.totalAssets();

        uint256 feeShares = vault.accruePerformanceFee();
        assertGt(feeShares, 0, "a profit above the mark must mint a fee");

        // Dilution only: totalAssets (the pool) is untouched, only totalSupply grew.
        assertEq(vault.totalAssets(), assetBalanceBefore, "assets must not move on fee accrual");
        assertEq(vault.totalSupply(), supplyBefore + feeShares, "fee is minted as new shares");
        assertEq(vault.balanceOf(feeRecipient), feeRecipientBefore + feeShares, "fee to recipient");
        assertEq(vault.highWaterMark(), navBefore, "HWM ratchets to the pre-mint NAV");
    }

    function test_forfeitureOnConfirmedBreach() public {
        seedScenario();

        // First establish a profit so a fee would otherwise be due.
        uint256 navBefore = vault.navPerShare();
        vm.store(address(vault), bytes32(uint256(8)), bytes32((navBefore * 99) / 100));
        uint256 feeShares = vault.accruePerformanceFee();
        assertGt(feeShares, 0);

        // Now confirm a breach with two consecutive extreme observations.
        feed.setAnswer(int256((MARK * 80) / 100), block.timestamp);
        assertEq(hook.updateRiskState(poolId), uint8(SkylineTypes.RiskState.Restricted));
        assertEq(hook.updateRiskState(poolId), uint8(SkylineTypes.RiskState.Breached));

        uint256 hwmBefore = vault.highWaterMark();
        uint256 supplyBefore = vault.totalSupply();
        uint256 feeRecipientBefore = vault.balanceOf(feeRecipient);

        // A confirmed breach forfeits the fee: no shares minted, HWM never falls.
        assertEq(vault.accruePerformanceFee(), 0);

        assertEq(vault.totalSupply(), supplyBefore, "no minting on forfeiture");
        assertEq(vault.balanceOf(feeRecipient), feeRecipientBefore, "recipient unchanged");
        assertGe(vault.highWaterMark(), hwmBefore, "HWM must never fall");
    }

    function test_singleExtremePrintDoesNotForfeit() public {
        seedScenario();

        // A single extreme print only reaches Restricted, not Breached. Trigger it BEFORE any
        // fee accrual so the NAV has not been collapsed by a prior mint.
        feed.setAnswer(int256((MARK * 80) / 100), block.timestamp);
        assertEq(hook.updateRiskState(poolId), uint8(SkylineTypes.RiskState.Restricted));
        assertEq(hook.effectiveRiskState(poolId), uint8(SkylineTypes.RiskState.Restricted));

        // Restricted does not forfeit: the fee still accrues if there is profit.
        uint256 navBefore2 = vault.navPerShare();
        vm.store(address(vault), bytes32(uint256(8)), bytes32((navBefore2 * 99) / 100));
        assertGt(vault.accruePerformanceFee(), 0, "Restricted must not forfeit the fee");
    }
}
