// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PositionInfo} from "v4-periphery/src/libraries/PositionInfoLibrary.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {SqrtPriceMath} from "v4-core/libraries/SqrtPriceMath.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {PoolVaultManager} from "./PoolVaultManager.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";

contract PoolPartyDynamicShieldHook is BaseHook {
    IPositionManager s_positionManager;
    PoolVaultManager s_vaultManager;
    mapping(PoolId => ShieldInfo) public shieldInfos;
    mapping(PoolId => int24) public lastTicks;
    mapping(PoolId => uint24) public lastFees;

    struct CallData {
        PoolKey key;
        uint24 feeInit;
        uint24 feeMax;
        TickSpacing tickSpacing;
    }

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

    // Errors
    error InvalidPositionManager();
    error InvalidSelf();

    // Initialize BaseHook parent contract in the constructor
    constructor(
        IPoolManager _poolManager,
        IPositionManager _positionManager
    ) BaseHook(_poolManager) {
        s_positionManager = _positionManager;
        s_vaultManager = new PoolVaultManager(address(this), _positionManager);
    }

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

    function initializeShieldTokenHolder(
        PoolKey calldata _poolKey,
        TickSpacing _tickSpacing,
        uint24 _feeInit,
        uint24 _feeMax,
        uint256 _tokenId
    ) external {
        IERC721(address(s_positionManager)).safeTransferFrom(
            msg.sender,
            address(this),
            _tokenId,
            abi.encode(
                CallData({
                    key: _poolKey,
                    feeInit: _feeInit,
                    feeMax: _feeMax,
                    tickSpacing: _tickSpacing
                })
            )
        );
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
        PoolId poolId = PoolIdLibrary.toId(poolKey);
        (uint160 currentSqrtPriceX96, , , ) = StateLibrary.getSlot0(
            poolManager,
            poolId
        );
        uint24 fee = getFee(poolKey, currentSqrtPriceX96);
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
    ) external override returns (bytes4, int128) {
        //TODO Check events/parameters and if it should be here.
        //Get last tick
        //Emit tick event
        //Get Shield
        //Emit Register Shield event  (FeeMax, TokenHold, TokenId)
        return (this.afterSwap.selector, 0);
    }

    function onERC721Received(
        address _operator,
        address _from,
        uint256 _tokenId,
        bytes calldata _data
    ) external returns (bytes4) {
        // Check if the sender is the position manager
        if (msg.sender != address(s_positionManager))
            revert InvalidPositionManager();
        if (_operator != address(this)) revert InvalidSelf();

        CallData memory data = abi.decode(_data, (CallData));

        (, PositionInfo info) = s_positionManager.getPoolAndPositionInfo(
            _tokenId
        );

        PoolId poolId = PoolIdLibrary.toId(data.key);
        shieldInfos[poolId] = ShieldInfo({
            tickSpacing: data.tickSpacing,
            feeInit: data.feeInit,
            feeMax: data.feeMax,
            tokenId: _tokenId
        });

        IERC721(address(s_positionManager)).approve(
            address(s_vaultManager),
            _tokenId
        );
        s_vaultManager.depositPosition(data.key, _tokenId, _from);

        return this.onERC721Received.selector;
    }

    function getFee(
        PoolKey calldata poolKey,
        uint160 sqrtPriceX96
    ) internal returns (uint24) {
        PoolId poolId = PoolIdLibrary.toId(poolKey);
        // Get the current sqrtPrice
        uint160 currentSqrtPriceX96 = sqrtPriceX96;
        // Get the current tick value from sqrtPriceX96
        int24 currentTick = getTickFromSqrtPrice(currentSqrtPriceX96);

        // Ensure `lastTicks` is initialized
        int24 lastTick = lastTicks[poolId];

        // Calculate diffTicks (absolute difference between currentTick and lastTick)
        int24 diffTicks = currentTick > lastTick
            ? currentTick - lastTick
            : lastTick - currentTick;

        // Ensure diffTicks is non-negative (redundant because the subtraction handles it)
        require(diffTicks >= 0, "diffTicks cannot be negative");

        int24 tickSpacing = getTickSpacingValue(
            shieldInfos[poolId].tickSpacing
        );

        //TODO: Evaluate how to calculate tickLower
        // Calculate tickLower and tickUpper
        int24 tickLower = tickSpacing * (currentTick / tickSpacing);
        int24 tickUpper = tickLower + tickSpacing; // Next tick boundary

        // Calculate totalTicks (absolute difference between tickUpper and tickLower)
        int24 totalTicks = tickUpper > tickLower
            ? tickUpper - tickLower
            : tickLower - tickUpper;

        // Prevent totalTicks from being too small to avoid division issues
        totalTicks = totalTicks < 2 ? int24(2) : totalTicks;

        // Get fee
        uint24 feeInit = shieldInfos[poolId].feeInit;
        uint24 feeMax = shieldInfos[poolId].feeMax;

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
        lastFees[poolId] = newFee;
        lastTicks[poolId] = currentTick;

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
