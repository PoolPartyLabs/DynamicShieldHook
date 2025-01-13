// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "../../interfaces/INonfungiblePositionManager.sol";
import "./LiquidityAmounts.sol";
import "./Tick.sol";
import "./FixedPoint128.sol";
import "./PoolAddress.sol";

/// @title Returns information about the token value held in a Uniswap V3 NFT
library PositionValue {
    /// @notice Returns the total amounts of currency0 and currency1, i.e. the sum of fees and principal
    /// that a given nonfungible position manager token is worth
    /// @param positionManager The Uniswap V3 NonfungiblePositionManager
    /// @param tokenId The tokenId of the token for which to get the total value
    /// @param sqrtRatioX96 The square root price X96 for which to calculate the principal amounts
    /// @return amount0 The total amount of currency0 including principal and fees
    /// @return amount1 The total amount of currency1 including principal and fees
    function total(
        INonfungiblePositionManager positionManager,
        uint256 tokenId,
        uint160 sqrtRatioX96
    ) internal view returns (uint256 amount0, uint256 amount1) {
        (uint256 amount0Principal, uint256 amount1Principal) = principal(
            positionManager,
            tokenId,
            sqrtRatioX96
        );
        (uint256 amount0Fee, uint256 amount1Fee) = fees(
            positionManager,
            tokenId
        );
        return (amount0Principal + amount0Fee, amount1Principal + amount1Fee);
    }

    /// @notice Calculates the principal (currently acting as liquidity) owed to the token owner in the event
    /// that the position is burned
    /// @param positionManager The Uniswap V3 NonfungiblePositionManager
    /// @param tokenId The tokenId of the token for which to get the total principal owed
    /// @param sqrtRatioX96 The square root price X96 for which to calculate the principal amounts
    /// @return amount0 The principal amount of currency0
    /// @return amount1 The principal amount of currency1
    // aderyn-ignore-next-line(useless-internal-function)
    function principal(
        INonfungiblePositionManager positionManager,
        uint256 tokenId,
        uint160 sqrtRatioX96
    ) internal view returns (uint256 amount0, uint256 amount1) {
        // slither-disable-start unused-return
        (
            ,
            ,
            ,
            ,
            ,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            ,
            ,
            ,

        ) = positionManager.positions(tokenId);
        // slither-disable-end unused-return

        // slither-disable-start unused-return
        return
            LiquidityAmounts.getAmountsForLiquidity(
                sqrtRatioX96,
                TickMath.getSqrtRatioAtTick(tickLower),
                TickMath.getSqrtRatioAtTick(tickUpper),
                liquidity
            );
        // slither-disable-end unused-return
    }

    struct FeeParams {
        address currency0;
        address currency1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint256 positionFeeGrowthInside0LastX128;
        uint256 positionFeeGrowthInside1LastX128;
        uint256 tokensOwed0;
        uint256 tokensOwed1;
    }

    /// @notice Calculates the total fees owed to the token owner
    /// @param positionManager The Uniswap V3 NonfungiblePositionManager
    /// @param tokenId The tokenId of the token for which to get the total fees owed
    /// @return amount0 The amount of fees owed in currency0
    /// @return amount1 The amount of fees owed in currency1
    // aderyn-ignore-next-line(useless-internal-function)
    function fees(
        INonfungiblePositionManager positionManager,
        uint256 tokenId
    ) internal view returns (uint256 amount0, uint256 amount1) {
        // slither-disable-next-line unused-return
        (
            ,
            ,
            address currency0,
            address currency1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 positionFeeGrowthInside0LastX128,
            uint256 positionFeeGrowthInside1LastX128,
            uint256 tokensOwed0,
            uint256 tokensOwed1
        ) = positionManager.positions(tokenId);

        return
            _fees(
                positionManager,
                FeeParams({
                    currency0: currency0,
                    currency1: currency1,
                    fee: fee,
                    tickLower: tickLower,
                    tickUpper: tickUpper,
                    liquidity: liquidity,
                    positionFeeGrowthInside0LastX128: positionFeeGrowthInside0LastX128,
                    positionFeeGrowthInside1LastX128: positionFeeGrowthInside1LastX128,
                    tokensOwed0: tokensOwed0,
                    tokensOwed1: tokensOwed1
                })
            );
    }

    function _fees(
        INonfungiblePositionManager positionManager,
        FeeParams memory feeParams
    ) private view returns (uint256 amount0, uint256 amount1) {
        (
            uint256 poolFeeGrowthInside0LastX128,
            uint256 poolFeeGrowthInside1LastX128
        ) = _getFeeGrowthInside(
                IUniswapV3Pool(
                    PoolAddress.computeAddress(
                        positionManager.factory(),
                        PoolAddress.PoolKey({
                            currency0: feeParams.currency0,
                            currency1: feeParams.currency1,
                            fee: feeParams.fee
                        })
                    )
                ),
                feeParams.tickLower,
                feeParams.tickUpper
            );
        amount0 =
            FullMath.mulDiv(
                subIn256(
                    poolFeeGrowthInside0LastX128,
                    feeParams.positionFeeGrowthInside0LastX128
                ),
                feeParams.liquidity,
                FixedPoint128.Q128
            ) +
            feeParams.tokensOwed0;

        amount1 =
            FullMath.mulDiv(
                subIn256(
                    poolFeeGrowthInside1LastX128,
                    feeParams.positionFeeGrowthInside1LastX128
                ),
                feeParams.liquidity,
                FixedPoint128.Q128
            ) +
            feeParams.tokensOwed1;
    }

    function _getFeeGrowthInside(
        IUniswapV3Pool pool,
        int24 tickLower,
        int24 tickUpper
    )
        private
        view
        returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128)
    {
        // slither-disable-next-line unused-return
        (, int24 tickCurrent, , , , , ) = pool.slot0();

        // slither-disable-next-line unused-return
        (
            ,
            ,
            uint256 lowerFeeGrowthOutside0X128,
            uint256 lowerFeeGrowthOutside1X128,
            ,
            ,
            ,

        ) = pool.ticks(tickLower);

        // slither-disable-next-line unused-return
        (
            ,
            ,
            uint256 upperFeeGrowthOutside0X128,
            uint256 upperFeeGrowthOutside1X128,
            ,
            ,
            ,

        ) = pool.ticks(tickUpper);
        uint256 feeGrowthGlobal0X128 = pool.feeGrowthGlobal0X128();
        uint256 feeGrowthGlobal1X128 = pool.feeGrowthGlobal1X128();

        uint256 feeGrowthBelow0X128;
        uint256 feeGrowthBelow1X128;
        if (tickCurrent >= tickLower) {
            feeGrowthBelow0X128 = lowerFeeGrowthOutside0X128;
            feeGrowthBelow1X128 = lowerFeeGrowthOutside1X128;
        } else {
            feeGrowthBelow0X128 = subIn256(
                feeGrowthGlobal0X128,
                lowerFeeGrowthOutside0X128
            );
            feeGrowthBelow1X128 = subIn256(
                feeGrowthGlobal1X128,
                lowerFeeGrowthOutside1X128
            );
        }

        uint256 feeGrowthAbove0X128;
        uint256 feeGrowthAbove1X128;
        if (tickCurrent < tickUpper) {
            feeGrowthAbove0X128 = upperFeeGrowthOutside0X128;
            feeGrowthAbove1X128 = upperFeeGrowthOutside1X128;
        } else {
            feeGrowthAbove0X128 = subIn256(
                feeGrowthGlobal0X128,
                upperFeeGrowthOutside0X128
            );
            feeGrowthAbove1X128 = subIn256(
                feeGrowthGlobal1X128,
                upperFeeGrowthOutside1X128
            );
        }

        feeGrowthInside0X128 = subIn256(
            subIn256(feeGrowthGlobal0X128, feeGrowthBelow0X128),
            feeGrowthAbove0X128
        );
        feeGrowthInside1X128 = subIn256(
            subIn256(feeGrowthGlobal1X128, feeGrowthBelow1X128),
            feeGrowthAbove1X128
        );
    }

    /// @notice Subtracts two uint256
    /// @param a A uint256 representing the minuend.
    /// @param b A uint256 representing the subtrahend.
    /// @return The difference of the two parameters.
    function subIn256(uint256 a, uint256 b) internal pure returns (uint256) {
        if (b > a) {
            (uint256 r0, uint256 r1) = mul256x256(1 << 255, 2); // 2**255  * 2
            (r0, r1) = add512x512(r0, r1, int256(a) - int256(b), 0);
            return r0;
        } else {
            return a - b;
        }
    }

    /// @notice Calculates the product of two uint256
    /// @dev Used the chinese remainder theoreme
    /// @param a A uint256 representing the first factor.
    /// @param b A uint256 representing the second factor.
    /// @return r0 The result as an uint512. r0 contains the lower bits.
    /// @return r1 The higher bits of the result.
    function mul256x256(
        uint256 a,
        uint256 b
    ) public pure returns (uint256 r0, uint256 r1) {
        assembly {
            let mm := mulmod(a, b, not(0))
            r0 := mul(a, b)
            r1 := sub(sub(mm, r0), lt(mm, r0))
        }
    }

    /// @notice Calculates the difference of two uint512
    /// @param a0 A uint256 representing the lower bits of the first addend.
    /// @param a1 A uint256 representing the higher bits of the first addend.
    /// @param b0 A int256 representing the lower bits of the seccond addend.
    /// @param b1 A uint256 representing the higher bits of the seccond addend.
    /// @return r0 The result as an uint512. r0 contains the lower bits.
    /// @return r1 The higher bits of the result.
    function add512x512(
        uint256 a0,
        uint256 a1,
        int256 b0,
        uint256 b1
    ) public pure returns (uint256 r0, uint256 r1) {
        assembly {
            r0 := add(a0, b0)
            r1 := add(add(a1, b1), lt(r0, a0))
        }
    }
}
