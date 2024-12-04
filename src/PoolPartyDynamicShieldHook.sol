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
    using SqrtPriceMath for uint160;
    using PositionInfoLibrary for PositionInfo;
    using LPFeeLibrary for uint24;

    IPositionManager s_positionManager;
    PoolVaultManager s_vaultManager;
    IAllowanceTransfer s_permit2;
    uint24 public s_feeInit;
    uint24 public s_feeMax;
    mapping(PoolId => ShieldInfo) public s_shieldInfos;
    mapping(PoolId => uint256[]) public s_tokenIds;
    mapping(PoolId => mapping(int24 tick => TickInfo)) public s_tickInfos;

    struct TickInfo {
        PoolId poolId;
        int24 tick;
        uint128 liquidity;
        uint24 fee;
    }

    struct CallData {
        PoolKey key;
    }

    struct ShieldInfo {
        uint256 tokenId;
    }

    enum TickSpacing {
        Invalid, // 0
        Low, // 10
        Medium, // 60
        High // 200
    }

    // Errors
    error MustUseDynamicFee();
    error InvalidTickSpacing();
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
        IAllowanceTransfer _permit2,
        Currency _safeToken,
        uint24 _feeInit,
        uint24 _feeMax
    ) BaseHook(_poolManager) {
        s_positionManager = _positionManager;
        s_vaultManager = new PoolVaultManager(
            _poolManager,
            _positionManager,
            _permit2,
            _safeToken,
            address(this)
        );
        s_permit2 = _permit2;
        s_feeInit = _feeInit;
        s_feeMax = _feeMax;
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
                beforeInitialize: true,
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

    function initializeShield(
        PoolKey calldata _poolKey,
        uint256 _tokenId
    ) external {
        IERC721(address(s_positionManager)).safeTransferFrom(
            msg.sender,
            address(this),
            _tokenId,
            abi.encode(_poolKey)
        );
    }

    function beforeInitialize(
        address,
        PoolKey calldata key,
        uint160
    ) external pure override returns (bytes4) {
        // `.isDynamicFee()` function comes from using
        // the `SwapFeeLibrary` for `uint24`
        if (!key.fee.isDynamicFee()) revert MustUseDynamicFee();
        // revert if the tickSpacing is not valid
        isValidTickSpacing(key.tickSpacing);
        return this.beforeInitialize.selector;
    }

    function beforeSwap(
        address,
        PoolKey calldata _poolKey,
        IPoolManager.SwapParams calldata _params,
        bytes calldata
    )
        external
        override
        onlyPoolManager
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        PoolId poolId = _poolKey.toId();
        (uint160 currentSqrtPriceX96, , , ) = poolManager.getSlot0(poolId);
        int24 currentTick = TickMath.getTickAtSqrtPrice(currentSqrtPriceX96);

        TickInfo memory tickInfo = s_tickInfos[poolId][currentTick];
        uint24 fee = tickInfo.fee;

        poolManager.updateDynamicLPFee(_poolKey, fee);
        uint24 feeWithFlag = fee | LPFeeLibrary.OVERRIDE_FEE_FLAG;

        uint128 liquidity = poolManager.getLiquidity(poolId);
        console.log("beforeSwap.liquidity", liquidity);
        console.log("beforeSwap._params.zeroForOne", _params.zeroForOne);
        console.log(
            "beforeSwap._params.amountSpecified",
            _params.amountSpecified
        );
        console.log("beforeSwap.currentTick", currentTick);

        // uint160 nextSqrtPriceX96 = currentSqrtPriceX96
        //     .getNextSqrtPriceFromInput(
        //         liquidity,
        //         uint256(_params.amountSpecified),
        //         _params.zeroForOne
        //     );

        // int24 nextTick = TickMath.getTickAtSqrtPrice(nextSqrtPriceX96);
        // console.log("beforeSwap.nextTick", nextTick);

        // Emit tick event
        emit TickEvent(poolId, currentTick);

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
        PoolId poolId = _poolKey.toId();
        (uint160 currentSqrtPriceX96, , , ) = poolManager.getSlot0(poolId);

        int24 currentTick = TickMath.getTickAtSqrtPrice(currentSqrtPriceX96);
        console.log("afterSwap.currentTick", currentTick);
        if (currentTick == -2) {
            uint256[] memory _tokenIds = s_tokenIds[poolId];
            s_vaultManager.removeLiquidityInBatch(poolId, _tokenIds);
        }

        return (this.afterSwap.selector, 0);
    }

    function onERC721Received(
        address _operator,
        address _from,
        uint256 _tokenId,
        bytes calldata _data
    ) external returns (bytes4) {
        if (msg.sender != address(s_positionManager))
            revert InvalidPositionManager();
        if (_operator != address(this)) revert InvalidSelf();

        PoolKey memory poolKey = abi.decode(_data, (PoolKey));
        PoolId poolId = poolKey.toId();

        (, PositionInfo info) = s_positionManager.getPoolAndPositionInfo(
            _tokenId
        );
        uint128 liquidity = s_positionManager.getPositionLiquidity(_tokenId);

        calcNewFeePerTick(
            poolId,
            liquidity,
            info.tickLower(),
            info.tickUpper(),
            s_feeInit,
            s_feeMax
        );

        s_shieldInfos[poolId] = ShieldInfo({tokenId: _tokenId});

        IERC721(address(s_positionManager)).approve(
            address(s_vaultManager),
            _tokenId
        );
        s_vaultManager.depositPosition(poolKey, _tokenId, _from);

        s_tokenIds[poolId].push(_tokenId);

        emit RegisterShieldEvent(poolId, s_feeMax, _tokenId, _from);

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
        (, PositionInfo info) = s_positionManager.getPoolAndPositionInfo(
            _tokenId
        );
        uint128 liquidity = s_positionManager.getPositionLiquidity(_tokenId);

        calcNewFeePerTick(
            _poolKey.toId(),
            liquidity,
            info.tickLower(),
            info.tickUpper(),
            s_feeInit,
            s_feeMax
        );
    }

    function removeLiquidity(
        PoolKey memory _poolKey,
        uint256 _tokenId,
        uint128 _percentage,
        uint256 _deadline
    ) external {
        s_vaultManager.removeLiquidity(
            _poolKey,
            _tokenId,
            _percentage,
            _deadline
        );
        (, PositionInfo info) = s_positionManager.getPoolAndPositionInfo(
            _tokenId
        );
        uint128 liquidity = s_positionManager.getPositionLiquidity(_tokenId);

        calcNewFeePerTick(
            _poolKey.toId(),
            liquidity,
            info.tickLower(),
            info.tickUpper(),
            s_feeInit,
            s_feeMax
        );
    }

    function collectFees(
        PoolKey memory _key,
        uint256 _tokenId,
        uint256 _deadline
    ) external {
        s_vaultManager.collectFees(_key, _tokenId, _deadline);
    }

    function getVaulManagerAddress() public view returns (address) {
        return address(s_vaultManager);
    }

    function getTickSpacingValue(
        TickSpacing _tickSpacing
    ) internal pure returns (int24) {
        if (_tickSpacing == TickSpacing.Low) {
            return 10;
        } else if (_tickSpacing == TickSpacing.Medium) {
            return 60;
        } else if (_tickSpacing == TickSpacing.High) {
            return 200;
        }
        revert InvalidTickSpacing();
    }

    function isValidTickSpacing(int24 _tickSpacing) internal pure {
        if (_tickSpacing != 10 && _tickSpacing != 60 && _tickSpacing != 200) {
            revert InvalidTickSpacing();
        }
    }

    function calcFeesPerTicks(
        uint24 _numTicks,
        uint24 _fee0,
        uint24 _feeMax
    ) internal pure returns (uint24[] memory) {
        uint24[] memory fees = new uint24[](_numTicks);
        fees[0] = _feeMax;
        fees[_numTicks - 1] = _feeMax;

        if (_numTicks % 2 == 0) {
            uint24 tickFee = _feeMax / (1 + (_numTicks - 2) / 2);
            for (uint24 i = 1; i < _numTicks - 1; i++) {
                fees[i] = tickFee;
            }
        } else {
            uint24 middle = _numTicks / 2;
            fees[middle] = _fee0;

            uint24 feeInc = (_feeMax - _fee0) / (_numTicks - 1) / 2;
            uint24 lastFee = _fee0;
            for (uint24 i = middle + 1; i < _numTicks - 1; i++) {
                fees[i] = lastFee + feeInc;
                lastFee = fees[i];
            }

            lastFee = _fee0;
            for (uint24 i = middle - 1; i > 0; i--) {
                fees[i] = lastFee + feeInc;
                lastFee = fees[i];
            }
        }
        return fees;
    }

    function calcNewFeePerTick(
        PoolId _poolId,
        uint128 _liquidity,
        int24 _tickLower,
        int24 _tickUpper,
        uint24 _fee0,
        uint24 _feeMax
    ) internal {
        uint24 _numTicks = uint24(_tickUpper - _tickLower) + 1;
        uint128 liqPerTick = (_liquidity / _numTicks);
        uint24[] memory feesPerTicks = calcFeesPerTicks(
            _numTicks,
            _fee0,
            _feeMax
        );
        uint24 tickIndex = 0;
        for (int24 i = _tickLower; i <= _tickUpper; i++) {
            TickInfo storage tickInfo = s_tickInfos[_poolId][i];

            tickInfo.fee = uint24(
                (feesPerTicks[tickIndex] * tickInfo.liquidity) +
                    (_feeMax * liqPerTick)
            );
            if (tickInfo.fee > _feeMax) {
                tickInfo.fee = _feeMax;
            }
            tickInfo.liquidity += liqPerTick;
            tickIndex++;
        }
    }
}
