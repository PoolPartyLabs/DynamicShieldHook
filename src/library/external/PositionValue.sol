// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
// import "../../interfaces/IPoolManager.sol";

/** Uniswap v4 Core */
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {FixedPoint128} from "v4-core/src/libraries/FixedPoint128.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";

/** Uniswap v4 Periphery */
import "./LiquidityAmounts.sol";

import {console} from "forge-std/Test.sol";

/// @title Returns information about the token value held in a Uniswap V3 NFT
library PositionValue {
    using StateLibrary for IPoolManager;

    struct FeeParams {
        PoolId poolId;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint256 positionFeeGrowthInside0LastX128;
        uint256 positionFeeGrowthInside1LastX128;
    }

    /// @notice Calculates the total fees owed to the token owner
    /// @param poolManager The Uniswap V3 PoolManager
    /// @param poolId The poolId of the pool for which to calculate the fees
    /// @param tokenId The tokenId of the token for which to calculate the fees
    function fees(
        IPoolManager poolManager,
        PoolId poolId,
        address owner,
        uint256 tokenId,
        int24 tickLower,
        int24 tickUpper
    ) internal view returns (uint256 amount0, uint256 amount1) {
        (
            uint128 liquidity,
            uint256 positionFeeGrowthInside0LastX128,
            uint256 positionFeeGrowthInside1LastX128
        ) = poolManager.getPositionInfo(
                poolId,
                owner,
                tickLower,
                tickUpper,
                bytes32(tokenId)
            );

        console.log();
        console.log("tokenId: %d", tokenId);
        console.log("liquidity: %d", liquidity);
        console.log(
            "positionFeeGrowthInside0LastX128: %d",
            positionFeeGrowthInside0LastX128
        );
        console.log(
            "positionFeeGrowthInside1LastX128: %d",
            positionFeeGrowthInside1LastX128
        );
        console.log();
        return
            _fees(
                poolManager,
                FeeParams({
                    poolId: poolId,
                    tickLower: tickLower,
                    tickUpper: tickUpper,
                    liquidity: liquidity,
                    positionFeeGrowthInside0LastX128: positionFeeGrowthInside0LastX128,
                    positionFeeGrowthInside1LastX128: positionFeeGrowthInside1LastX128
                })
            );
    }

    function _fees(
        IPoolManager poolManager,
        FeeParams memory feeParams
    ) private view returns (uint256 amount0, uint256 amount1) {
        (
            uint256 poolFeeGrowthInside0LastX128,
            uint256 poolFeeGrowthInside1LastX128
        ) = poolManager.getFeeGrowthInside(
                feeParams.poolId,
                feeParams.tickLower,
                feeParams.tickUpper
            );
        amount0 = FullMath.mulDiv(
            subIn256(
                poolFeeGrowthInside0LastX128,
                feeParams.positionFeeGrowthInside0LastX128
            ),
            feeParams.liquidity,
            FixedPoint128.Q128
        );

        amount1 = FullMath.mulDiv(
            subIn256(
                poolFeeGrowthInside1LastX128,
                feeParams.positionFeeGrowthInside1LastX128
            ),
            feeParams.liquidity,
            FixedPoint128.Q128
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
