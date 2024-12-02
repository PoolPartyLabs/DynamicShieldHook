// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/** Forge */
import {IERC721} from "forge-std/interfaces/IERC721.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

/** Uniswap v4 Core */
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {SqrtPriceMath} from "v4-core/src/libraries/SqrtPriceMath.sol";
import {LPFeeLibrary} from "v4-core/src/libraries/LPFeeLibrary.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";

/** Uniswap v4 Periphery */
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";
import {PositionInfo, PositionInfoLibrary} from "v4-periphery/src/libraries/PositionInfoLibrary.sol";

/** Intenral */
import {PoolVaultManager} from "./PoolVaultManager.sol";

import {console} from "forge-std/Test.sol";

contract PoolPartyDynamicShieldHook is BaseHook {
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;

    IPositionManager s_positionManager;
    PoolVaultManager s_vaultManager;
    IAllowanceTransfer s_permit2;
    mapping(PoolId => ShieldInfo) public shieldInfos;
    mapping(PoolId => int24) public lastTicks;
    mapping(PoolId => uint24) public lastFees;

    struct CallData {
        PoolKey key;
        uint24 feeInit;
        uint24 feeMax;
        TickSpacing tickSpacing;
        Currency safeToken;
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
        Currency safeToken;
    }

    // Errors
    error InvalidPositionManager();
    error InvalidSelf();

    //Events
    event TickEvent(PoolId poolId, int24 currentTick);

    // Event to register Shield information
    event RegisterShieldEvent(
        PoolId poolId,
        uint24 feeMax,
        uint256 tokenId,
        address holder
    );

    // Initialize BaseHook parent contract in the constructor
    constructor(
        IPoolManager _poolManager,
        IPositionManager _positionManager,
        IAllowanceTransfer _permit2
    ) BaseHook(_poolManager) {
        s_positionManager = _positionManager;
        s_vaultManager = new PoolVaultManager(
            _poolManager,
            _positionManager,
            _permit2,
            address(this)
        );
        s_permit2 = _permit2;
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
        Currency _safeToken,
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
                    tickSpacing: _tickSpacing,
                    safeToken: _safeToken
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
        PoolId poolId = poolKey.toId();
        (uint160 currentSqrtPriceX96, , , ) = poolManager.getSlot0(poolId);
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
        PoolKey calldata _poolKey,
        IPoolManager.SwapParams calldata,
        BalanceDelta,
        bytes calldata
    ) external override returns (bytes4, int128) {
        //TODO Check events/parameters and if it should be here.
        // Get last tick
        PoolId poolId = _poolKey.toId();
        int24 lastTick = lastTicks[poolId];

        // Emit tick event
        emit TickEvent(poolId, lastTick);

        // Get ShieldInfo for the current pool
        ShieldInfo memory shieldInfo = shieldInfos[poolId];

        // Emit Register Shield event (FeeMax, TokenHold, TokenId)
        emit RegisterShieldEvent(
            poolId,
            shieldInfo.feeMax,
            shieldInfo.tokenId,
            msg.sender // The operator who initiated the swap
        );

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

        // (, PositionInfo info) = s_positionManager.getPoolAndPositionInfo(
        //     _tokenId
        // );

        shieldInfos[data.key.toId()] = ShieldInfo({
            tickSpacing: data.tickSpacing,
            feeInit: data.feeInit,
            feeMax: data.feeMax,
            tokenId: _tokenId,
            safeToken: data.safeToken
        });

        IERC721(address(s_positionManager)).approve(
            address(s_vaultManager),
            _tokenId
        );
        s_vaultManager.depositPosition(
            data.key,
            data.safeToken,
            _tokenId,
            _from
        );

        return this.onERC721Received.selector;
    }

    function addLiquidty(
        PoolKey calldata _poolKey,
        uint256 _tokenId,
        uint256 _amount0,
        uint256 _amount1,
        uint256 _deadline
    ) external {
        IERC20(Currency.unwrap(_poolKey.currency0)).transferFrom(
            msg.sender,
            address(this),
            _amount0
        );
        IERC20(Currency.unwrap(_poolKey.currency1)).transferFrom(
            msg.sender,
            address(this),
            _amount1
        );
        IERC20(Currency.unwrap(_poolKey.currency0)).approve(
            address(s_vaultManager),
            _amount0
        );
        IERC20(Currency.unwrap(_poolKey.currency1)).approve(
            address(s_vaultManager),
            _amount1
        );
        s_vaultManager.addLiquidity(
            _poolKey,
            _tokenId,
            _amount0,
            _amount1,
            _deadline
        );
    }

    function removeLiquidity(
        PoolKey memory _key,
        uint256 _tokenId,
        uint128 _percentage,
        uint256 _deadline
    ) external {
        s_vaultManager.removeLiquidity(_key, _tokenId, _percentage, _deadline);
    }

    function collectFees(
        PoolKey memory _key,
        uint256 _tokenId,
        uint256 _deadline
    ) external {
        s_vaultManager.collectFees(_key, _tokenId, _deadline);
    }

    function swapTest(
        Currency _currencyIn,
        uint256 _tokenId,
        uint256 _amountIn,
        address _recipient
    ) public {
        IERC20(Currency.unwrap(_currencyIn)).transferFrom(
            msg.sender,
            address(this),
            _amountIn
        );
        IERC20(Currency.unwrap(_currencyIn)).approve(
            address(s_vaultManager),
            _amountIn
        );
        s_vaultManager._swapExactInputSingle(
            _currencyIn,
            _tokenId,
            _amountIn,
            _recipient
        );
    }

    function getVaulManagerAddress() public view returns (address) {
        return address(s_vaultManager);
    }

    function getFee(
        PoolKey calldata _poolKey,
        uint160 _sqrtPriceX96
    ) internal returns (uint24) {
        PoolId poolId = _poolKey.toId();
        // Get the current tick value from sqrtPriceX96
        int24 currentTick = getTickFromSqrtPrice(_sqrtPriceX96);

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
        uint160 _sqrtPriceX96
    ) internal pure returns (int24 tickValue) {
        // Ensure the sqrtPriceX96 value is within the valid range
        require(
            _sqrtPriceX96 >= TickMath.MIN_SQRT_PRICE &&
                _sqrtPriceX96 <= TickMath.MAX_SQRT_PRICE,
            "sqrtPriceX96 out of range"
        );

        // Calculate the tick value using TickMath
        tickValue = TickMath.getTickAtSqrtPrice(_sqrtPriceX96);
    }

    function getTickSpacingValue(
        TickSpacing _tickSpacing
    ) internal pure returns (int24) {
        if (_tickSpacing == TickSpacing.Low) {
            return 10;
        } else if (_tickSpacing == TickSpacing.Medium) {
            return 50;
        } else if (_tickSpacing == TickSpacing.High) {
            return 200;
        }
        revert("Invalid TickSpacing");
    }
}
