// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {SqrtPriceMath} from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import {FixedPoint96} from "@uniswap/v4-core/src/libraries/FixedPoint96.sol";
import {SafeCast} from "@uniswap/v4-core/src/libraries/SafeCast.sol";

/**
 * @title LiquidityAmounts
 * @notice Conversions between token amounts and concentrated-liquidity amounts.
 * @dev The standard Uniswap v3/v4 formulas, implemented here so the vault has no dependency on
 *      a periphery package whose release cadence does not match `v4-core`.
 *
 *      Every function is pure and independently testable; see
 *      `test/unit/LiquidityAmounts.t.sol`.
 */
library LiquidityAmounts {
    using SafeCast for uint256;

    /// @notice Liquidity received for a given amount of token0 across a price range.
    /// @param sqrtRatioAX96 The lower sqrt price (ordering is normalised internally).
    /// @param sqrtRatioBX96 The upper sqrt price.
    /// @param amount0 The token0 amount.
    /// @return liquidity The liquidity amount.
    function getLiquidityForAmount0(uint160 sqrtRatioAX96, uint160 sqrtRatioBX96, uint256 amount0)
        internal
        pure
        returns (uint128 liquidity)
    {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

        uint256 intermediate = FullMath.mulDiv(sqrtRatioAX96, FixedPoint96.Q96, sqrtRatioBX96);
        uint256 numerator = FullMath.mulDiv(amount0, FixedPoint96.Q96, sqrtRatioBX96 - intermediate);
        return numerator.toUint128();
    }

    /// @notice Liquidity received for a given amount of token1 across a price range.
    /// @param sqrtRatioAX96 The lower sqrt price (ordering is normalised internally).
    /// @param sqrtRatioBX96 The upper sqrt price.
    /// @param amount1 The token1 amount.
    /// @return liquidity The liquidity amount.
    function getLiquidityForAmount1(uint160 sqrtRatioAX96, uint160 sqrtRatioBX96, uint256 amount1)
        internal
        pure
        returns (uint128 liquidity)
    {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
        uint256 numerator = FullMath.mulDiv(amount1, FixedPoint96.Q96, sqrtRatioBX96 - sqrtRatioAX96);
        return numerator.toUint128();
    }

    /// @notice The token amounts owed by a liquidity position across a price range.
    /// @param sqrtRatioAX96 The lower sqrt price.
    /// @param sqrtRatioBX96 The upper sqrt price.
    /// @param liquidity The liquidity amount.
    /// @return amount0 The token0 amount.
    /// @return amount1 The token1 amount.
    function getAmountsForLiquidity(uint160 sqrtRatioAX96, uint160 sqrtRatioBX96, uint128 liquidity)
        internal
        pure
        returns (uint256 amount0, uint256 amount1)
    {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

        if (sqrtRatioAX96 == sqrtRatioBX96) {
            return (
                SqrtPriceMath.getAmount0Delta(sqrtRatioAX96, sqrtRatioBX96, liquidity, true),
                SqrtPriceMath.getAmount1Delta(sqrtRatioAX96, sqrtRatioBX96, liquidity, true)
            );
        }

        uint256 intermediate = FullMath.mulDiv(sqrtRatioBX96, liquidity, FixedPoint96.Q96);
        amount0 = SqrtPriceMath.getAmount0Delta(sqrtRatioAX96, sqrtRatioBX96, uint128(intermediate), true);
        amount1 = SqrtPriceMath.getAmount1Delta(sqrtRatioAX96, sqrtRatioBX96, liquidity - uint128(intermediate), true);
    }

    /// @notice The token0 amount owed by a liquidity position at a given price.
    /// @param sqrtPriceX96 The current sqrt price.
    /// @param sqrtRatioAX96 The lower sqrt price.
    /// @param sqrtRatioBX96 The upper sqrt price.
    /// @param liquidity The liquidity amount.
    /// @return amount0 The token0 amount.
    function getAmount0Delta(uint160 sqrtPriceX96, uint160 sqrtRatioAX96, uint160 sqrtRatioBX96, uint128 liquidity)
        internal
        pure
        returns (uint256 amount0)
    {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

        if (sqrtPriceX96 <= sqrtRatioAX96) {
            return SqrtPriceMath.getAmount0Delta(sqrtRatioAX96, sqrtRatioBX96, liquidity, true);
        }
        if (sqrtPriceX96 >= sqrtRatioBX96) {
            return SqrtPriceMath.getAmount0Delta(sqrtRatioAX96, sqrtRatioBX96, liquidity, true);
        }

        uint256 intermediate = FullMath.mulDiv(sqrtPriceX96, liquidity, FixedPoint96.Q96);
        uint256 amount0Intermediate = uint128(intermediate) < liquidity
            ? SqrtPriceMath.getAmount0Delta(sqrtPriceX96, sqrtRatioAX96, uint128(intermediate), true)
            : 0;
        uint256 amount0Remaining =
            SqrtPriceMath.getAmount0Delta(sqrtPriceX96, sqrtRatioBX96, liquidity - uint128(intermediate), true);
        return amount0Intermediate + amount0Remaining;
    }

    /// @notice The token1 amount owed by a liquidity position at a given price.
    /// @param sqrtPriceX96 The current sqrt price.
    /// @param sqrtRatioAX96 The lower sqrt price.
    /// @param sqrtRatioBX96 The upper sqrt price.
    /// @param liquidity The liquidity amount.
    /// @return amount1 The token1 amount.
    function getAmount1Delta(uint160 sqrtPriceX96, uint160 sqrtRatioAX96, uint160 sqrtRatioBX96, uint128 liquidity)
        internal
        pure
        returns (uint256 amount1)
    {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

        if (sqrtPriceX96 <= sqrtRatioAX96) {
            return SqrtPriceMath.getAmount1Delta(sqrtRatioAX96, sqrtRatioBX96, liquidity, true);
        }
        if (sqrtPriceX96 >= sqrtRatioBX96) {
            return SqrtPriceMath.getAmount1Delta(sqrtRatioAX96, sqrtRatioBX96, liquidity, true);
        }

        uint256 intermediate = FullMath.mulDiv(sqrtPriceX96, liquidity, FixedPoint96.Q96);
        uint256 amount1Remaining =
            SqrtPriceMath.getAmount1Delta(sqrtRatioAX96, sqrtPriceX96, liquidity - uint128(intermediate), true);
        return amount1Remaining;
    }
}
