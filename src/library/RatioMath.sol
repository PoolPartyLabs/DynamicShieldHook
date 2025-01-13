// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {PositionKey} from "../types/PositionKey.sol";
import "../interfaces/Constants.sol";
import "./uniswap/TickMath.sol";
import "./uniswap/FullMath.sol";
import "./uniswap/FixedPoint96.sol";

/**
 * @title RatioMath Library
 * @notice This library provides functions to calculate ratios and perform mathematical operations
 * related to Uniswap V3 pool positions.
 */
library RatioMath {
    /**
     * @notice Calculates the ratio between the current price and the price range
     * @param positionKey The  position key
     * @param sqrtPriceX96Current  The current price
     * @param inverted  If the currency0 and currency1 are inverted
     * @return _ratio The ratio between the current price and the price range
     * @dev The formula is: r = 1 / ((((sqrt(priceLow * priceHigh) - sqrt(priceHigh * priceCurrent)) / (priceCurrent - sqrt(priceHigh * priceCurrent))) + 1))
     * We return the result multiplied by 1e22 to have 4 decimals of precision in the result and
     * we should divide by 10_000 to get the actual ratio. Example: 5 is 0,0005
     */
    function ratio(
        PositionKey memory positionKey,
        uint160 sqrtPriceX96Current,
        bool inverted
    ) external view returns (uint256 _ratio) {
        address currency0 = positionKey.currency0;
        address currency1 = positionKey.currency1;
        int24 tickLow = positionKey.tickLower;
        int24 tickHigh = positionKey.tickUpper;

        uint256 sqrtPriceX96Low = TickMath.getSqrtRatioAtTick(tickLow);
        uint256 sqrtPriceX96High = TickMath.getSqrtRatioAtTick(tickHigh);

        int16 decimalsDiff = int16(
            int8(ERC20(currency0).decimals()) -
                int8(ERC20(currency1).decimals())
        );
        uint256 decimals = decimalsDiff < 0
            ? uint256(10 ** uint16(-decimalsDiff)) // aderyn-ignore(literal-instead-of-constant)
            : uint256(10 ** uint16(decimalsDiff)); // aderyn-ignore(literal-instead-of-constant)

        uint256 priceLow = ((FullMath.mulDiv(
            sqrtPriceX96Low,
            DENOMINATOR_MULTIPLIER,
            FixedPoint96.Q96
        ) ** 2) / decimals) / DENOMINATOR_MULTIPLIER;

        if (priceLow == 0) {
            priceLow =
                ((FullMath.mulDiv(
                    sqrtPriceX96Low,
                    DENOMINATOR_MULTIPLIER,
                    FixedPoint96.Q96
                ) ** 2) * decimals) /
                DENOMINATOR_MULTIPLIER;
        }

        uint256 priceHigh = ((FullMath.mulDiv(
            sqrtPriceX96High,
            DENOMINATOR_MULTIPLIER,
            FixedPoint96.Q96
        ) ** 2) / decimals) / DENOMINATOR_MULTIPLIER;

        if (priceHigh == 0) {
            priceHigh =
                ((FullMath.mulDiv(
                    sqrtPriceX96High,
                    DENOMINATOR_MULTIPLIER,
                    FixedPoint96.Q96
                ) ** 2) * decimals) /
                DENOMINATOR_MULTIPLIER;
        }

        uint256 priceCurrent = ((FullMath.mulDiv(
            sqrtPriceX96Current,
            DENOMINATOR_MULTIPLIER,
            FixedPoint96.Q96
        ) ** 2) / decimals) / DENOMINATOR_MULTIPLIER;

        if (priceCurrent == 0) {
            priceCurrent =
                ((FullMath.mulDiv(
                    sqrtPriceX96Current,
                    DENOMINATOR_MULTIPLIER,
                    FixedPoint96.Q96
                ) ** 2) * decimals) /
                DENOMINATOR_MULTIPLIER;
        }

        if (priceCurrent < priceLow) {
            return inverted ? 0 : 10e3; // aderyn-ignore(literal-instead-of-constant)
        } else if (priceCurrent > priceHigh) {
            return inverted ? 10e3 : 0; // aderyn-ignore(literal-instead-of-constant)
        }

        int256 sqrtPriceHighTimesCurrent = int256(
            _sqrt(priceHigh * priceCurrent)
        );

        int256 A = int256(_sqrt(priceLow * priceHigh)) -
            sqrtPriceHighTimesCurrent;
        if (A < 0) {
            A = -A;
        }

        int256 B = (int256(priceCurrent) - sqrtPriceHighTimesCurrent);
        if (B < 0) {
            B = -B;
        }

        int256 C = ((A * int256(DENOMINATOR_MULTIPLIER)) / B) +
            (1 * int256(DENOMINATOR_MULTIPLIER));
        // 1e22 to have 4 decimals of precision in the result
        // aderyn-ignore-next-line(literal-instead-of-constant)
        _ratio = (1e22 / uint256(C));
        if (inverted) {
            _ratio =
                // aderyn-ignore-next-line(literal-instead-of-constant)
                10e3 -
                /**
                 * 10_000
                 */
                _ratio; // aderyn-ignore(literal-instead-of-constant)
        }
    }

    function _ceil(uint256 a, uint256 m) external pure returns (uint256 r) {
        return ((a + m - 1) / m) * m;
    }

    /// @notice Calculates the square root of x, rounding down.
    /// @dev Uses the Babylonian method https://en.wikipedia.org/wiki/Methods_of_computing_square_roots#Babylonian_method.
    /// @param x The uint256 number for which to calculate the square root.
    /// @return result The result as an uint256.
    function _sqrt(uint256 x) public pure returns (uint256 result) {
        if (x == 0) {
            return 0;
        }

        // Calculate the square root of the perfect square of a power of two that is the closest to x.
        uint256 xAux = uint256(x);
        result = 1;
        if (xAux >= 0x100000000000000000000000000000000) {
            xAux >>= 128; // aderyn-ignore(literal-instead-of-constant)
            result <<= 64; // aderyn-ignore(literal-instead-of-constant)
        }
        if (xAux >= 0x10000000000000000) {
            xAux >>= 64; // aderyn-ignore(literal-instead-of-constant)
            result <<= 32; // aderyn-ignore(literal-instead-of-constant)
        }
        if (xAux >= 0x100000000) {
            xAux >>= 32; // aderyn-ignore(literal-instead-of-constant)
            result <<= 16; // aderyn-ignore(literal-instead-of-constant)
        }
        if (xAux >= 0x10000) {
            xAux >>= 16; // aderyn-ignore(literal-instead-of-constant)
            result <<= 8; // aderyn-ignore(literal-instead-of-constant)
        }
        if (xAux >= 0x100) {
            xAux >>= 8; // aderyn-ignore(literal-instead-of-constant)
            result <<= 4; // aderyn-ignore(literal-instead-of-constant)
        }
        if (xAux >= 0x10) {
            xAux >>= 4; // aderyn-ignore(literal-instead-of-constant)
            result <<= 2; // aderyn-ignore(literal-instead-of-constant)
        }
        if (xAux >= 0x8) {
            result <<= 1; // aderyn-ignore(literal-instead-of-constant)
        }

        // The operations can never overflow because the result is max 2^127 when it enters this block.
        unchecked {
            result = (result + x / result) >> 1;
            result = (result + x / result) >> 1;
            result = (result + x / result) >> 1;
            result = (result + x / result) >> 1;
            result = (result + x / result) >> 1;
            result = (result + x / result) >> 1;
            result = (result + x / result) >> 1; // Seven iterations should be enough
            uint256 roundedDownResult = x / result;
            return result >= roundedDownResult ? roundedDownResult : result;
        }
    }
}
