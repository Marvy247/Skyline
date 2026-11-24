// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SkylineFixture} from "../utils/SkylineFixture.sol";
import {SkylineHook} from "../../src/SkylineHook.sol";
import {SkylineTypes} from "../../src/libraries/SkylineTypes.sol";

/**
 * @title MandateTest
 * @notice Mandates are fixed once a pool carries liquidity, except that the owner may
 *         always tighten one. Loosening requires an empty pool.
 */
contract MandateTest is SkylineFixture {
    function _baseMandate() internal view returns (SkylineTypes.Mandate memory) {
        return SkylineTypes.Mandate({
            maxFeeBps: 3000,
            bandLower: TICK_LOWER - 60,
            bandUpper: TICK_UPPER + 60,
            minSkinBps: 1000,
            maxDrawdownBps: 1000,
            claimTtl: 1 days,
            riskState: uint8(SkylineTypes.RiskState.Normal)
        });
    }

    function test_tighteningAllowedWithLiquidity() public {
        seedScenario();

        SkylineTypes.Mandate memory tighter = _baseMandate();
        tighter.maxFeeBps = 2000;
        tighter.bandLower = TICK_LOWER; // narrower lower
        tighter.bandUpper = TICK_UPPER; // narrower upper
        tighter.minSkinBps = 2000;
        tighter.maxDrawdownBps = 500;
        tighter.claimTtl = 12 hours;

        vm.prank(owner);
        hook.setMandate(poolId, tighter);

        assertEq(hook.mandate(poolId).maxFeeBps, 2000);
        assertEq(hook.mandate(poolId).minSkinBps, 2000);
    }

    function test_looseningRejectedWithLiquidity() public {
        seedScenario();

        SkylineTypes.Mandate memory looser = _baseMandate();
        looser.maxFeeBps = 4000; // looser fee cap

        vm.prank(owner);
        vm.expectRevert(SkylineHook.InvalidMandate.selector);
        hook.setMandate(poolId, looser);
    }

    function test_looseningBandRejectedWithLiquidity() public {
        seedScenario();

        SkylineTypes.Mandate memory looser = _baseMandate();
        looser.bandLower = TICK_LOWER - 120; // wider

        vm.prank(owner);
        vm.expectRevert(SkylineHook.InvalidMandate.selector);
        hook.setMandate(poolId, looser);
    }

    function test_riskStatePreservedOnMandateEdit() public {
        seedScenario();

        SkylineTypes.Mandate memory tighter = _baseMandate();
        tighter.maxFeeBps = 2000;

        vm.prank(owner);
        hook.setMandate(poolId, tighter);

        // riskState stays as it was (Normal) regardless of what the caller passes.
        assertEq(hook.mandate(poolId).riskState, uint8(SkylineTypes.RiskState.Normal));
    }

    function test_fullReplaceAllowedWhenPoolIsEmpty() public {
        // No liquidity yet: any valid mandate is accepted.
        SkylineTypes.Mandate memory m = _baseMandate();
        m.maxFeeBps = 5000; // would be loosening relative to default, but pool is empty

        vm.prank(owner);
        hook.setMandate(poolId, m);

        assertEq(hook.mandate(poolId).maxFeeBps, 5000);
    }
}
