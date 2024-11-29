// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {SqrtPriceMath} from "v4-core/libraries/SqrtPriceMath.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";

contract PoolPartyDynamicShieldHook is BaseHook {
    mapping(bytes32 => ShieldInfo) public shieldInfos;
    mapping(bytes32 => int24) public lastTicks;
    mapping(bytes32 => uint24) public lastFees;

    enum TickSpacing {
        Low, // 10
        Medium, // 50
        High // 200
    }

    struct ShieldInfo {
        TickSpacing tickSpacing; // Enum for tick space
        uint24 feeInit; // Minimum fee
        uint24 feeMax; // Maximum fee
        uint256 tokenId; // Associated token ID
    }

    // Initialize BaseHook parent contract in the constructor
    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

    // Required override function for BaseHook to let the PoolManager know which hooks are implemented
    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterAddLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: true,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    // Function to generate a hash for a PoolKey
    function getPoolKeyHash(
        PoolKey calldata poolKey
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(poolKey.currency0, poolKey.currency1));
    }

    //TODO: Check if initialize parameters is ok
    function initializeShieldTokenHolder(
        PoolKey calldata poolKey,
        TickSpacing tickSpacing,
        uint24 feeInit,
        uint24 feeMax,
        uint256 tokenId
    ) external {
        bytes32 keyHash = getPoolKeyHash(poolKey);
        shieldInfos[keyHash] = ShieldInfo({
            tickSpacing: tickSpacing,
            feeInit: feeInit,
            feeMax: feeMax,
            tokenId: tokenId
        });
    }

    function beforeSwap(
        address,
        PoolKey calldata poolKey,
        IPoolManager.SwapParams calldata params,
        bytes calldata
    )
        external
        override
        onlyPoolManager
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        //TODO: Check if params.sqrtPriceLimitX96 represent current sqrtPrice
        uint24 fee = getFee(poolKey, params.sqrtPriceLimitX96);
        poolManager.updateDynamicLPFee(poolKey, fee);
        uint24 feeWithFlag = fee | LPFeeLibrary.OVERRIDE_FEE_FLAG;
        return (
            this.beforeSwap.selector,
            BeforeSwapDeltaLibrary.ZERO_DELTA,
            feeWithFlag
        );
    }

    function afterSwap(
        address,
        PoolKey calldata,
        IPoolManager.SwapParams calldata,
        BalanceDelta,
        bytes calldata
    ) external pure override returns (bytes4, int128) {
        return (this.afterSwap.selector, 0);
    }

    function getFee(
        PoolKey calldata poolKey,
        uint160 sqrtPriceX96
    ) internal returns (uint24) {
        bytes32 keyHash = getPoolKeyHash(poolKey);
        // Get the current sqrtPrice
        uint160 currentSqrtPriceX96 = sqrtPriceX96;
        // Get the current tick value from sqrtPriceX96
        int24 currentTick = getTickFromSqrtPrice(currentSqrtPriceX96);

        // Ensure `lastTicks` is initialized
        int24 lastTick = lastTicks[keyHash];

        // Calculate diffTicks (absolute difference between currentTick and lastTick)
        int24 diffTicks = currentTick > lastTick
            ? currentTick - lastTick
            : lastTick - currentTick;

        // Ensure diffTicks is non-negative (redundant because the subtraction handles it)
        require(diffTicks >= 0, "diffTicks cannot be negative");

        int24 tickSpacing = getTickSpacingValue(
            shieldInfos[keyHash].tickSpacing
        );

        // Calculate tickLower and tickUpper
        int24 tickLower = (currentTick / tickSpacing) * tickSpacing; // Round down to nearest tick spacing
        int24 tickUpper = tickLower + tickSpacing; // Next tick boundary

        // Calculate totalTicks (absolute difference between tickUpper and tickLower)
        int24 totalTicks = tickUpper > tickLower
            ? tickUpper - tickLower
            : tickLower - tickUpper;

        // Prevent totalTicks from being too small to avoid division issues
        totalTicks = totalTicks < 2 ? int24(2) : totalTicks;

        // Get fee
        uint24 feeInit = shieldInfos[keyHash].feeInit;
        uint24 feeMax = shieldInfos[keyHash].feeMax;

        // Ensure FeeInit is less than or equal to feeMax
        require(
            feeMax >= feeInit,
            "feeMax must be greater than or equal to initFee"
        );
        // Calculate the new fee
        uint24 newFee = uint24(diffTicks) *
            ((feeMax - feeInit) / uint24(totalTicks / 2));

        //TODO: Check if set last fee and tick here
        // Store last fee and tick
        lastFees[keyHash] = newFee;
        lastTicks[keyHash] = currentTick;

        return newFee;
    }

    function getTickFromSqrtPrice(
        uint160 sqrtPriceX96
    ) public pure returns (int24 tickValue) {
        // Ensure the sqrtPriceX96 value is within the valid range
        require(
            sqrtPriceX96 >= TickMath.MIN_SQRT_PRICE &&
                sqrtPriceX96 <= TickMath.MAX_SQRT_PRICE,
            "sqrtPriceX96 out of range"
        );

        // Calculate the tick value using TickMath
        tickValue = TickMath.getTickAtSqrtPrice(sqrtPriceX96);
    }

    function getTickSpacingValue(
        TickSpacing tickSpacing
    ) public pure returns (int24) {
        if (tickSpacing == TickSpacing.Low) {
            return 10;
        } else if (tickSpacing == TickSpacing.Medium) {
            return 50;
        } else if (tickSpacing == TickSpacing.High) {
            return 200;
        }
        revert("Invalid TickSpacing");
    }
}
