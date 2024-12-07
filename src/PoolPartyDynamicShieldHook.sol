// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/** OpenZeppelin Contracts */
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

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
import {BaseHook, IHooks} from "v4-periphery/src/base/hooks/BaseHook.sol";
import {PositionInfo, PositionInfoLibrary} from "v4-periphery/src/libraries/PositionInfoLibrary.sol";

/** Internal */
import {PoolVaultManager} from "./PoolVaultManager.sol";
import {IDynamicShieldAVS} from "./eigenlayer/IDynamicShieldAVS.sol";
import {IFeeManager} from "./interfaces/IFeeManager.sol";
import {IPoolPartyDynamicShieldHook} from "./interfaces/IPoolPartyDynamicShieldHook.sol";

import {console} from "forge-std/Test.sol";

contract PoolPartyDynamicShieldHook is
    IPoolPartyDynamicShieldHook,
    BaseHook,
    Ownable
{
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;
    using SqrtPriceMath for uint160;
    using PositionInfoLibrary for PositionInfo;
    using LPFeeLibrary for uint24;

    IPositionManager s_positionManager;
    PoolVaultManager s_vaultManager;
    IAllowanceTransfer s_permit2;
    IFeeManager s_feeManager;
    IDynamicShieldAVS s_dynamicShieldAVS;
    uint24 public s_feeInit;
    uint24 public s_feeMax;
    mapping(PoolId => ShieldInfo) public s_shieldInfos;
    mapping(PoolId => uint256[]) public s_tokenIds;
    mapping(PoolId => mapping(int24 tick => TickInfo)) public s_tickInfos;

    modifier onlyAVS() {
        if (msg.sender != address(s_dynamicShieldAVS)) revert InvalidAVS();
        _;
    }

    // Initialize BaseHook parent contract in the constructor
    constructor(
        IPoolManager _poolManager,
        IPositionManager _positionManager,
        IAllowanceTransfer _permit2,
        IFeeManager _feeManager,
        Currency _safeToken,
        uint24 _feeInit,
        uint24 _feeMax,
        address _initialOwner
    ) BaseHook(_poolManager) Ownable(_initialOwner) {
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
        s_feeManager = _feeManager;
    }

    function setAVS(address _avs) external onlyOwner {
        s_dynamicShieldAVS = IDynamicShieldAVS(_avs);
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
    ) external pure override(BaseHook, IHooks) returns (bytes4) {
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
        override(BaseHook, IHooks)
        onlyPoolManager
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        PoolId poolId = _poolKey.toId();
        (uint160 currentSqrtPriceX96, , , ) = poolManager.getSlot0(poolId);
        int24 currentTick = TickMath.getTickAtSqrtPrice(currentSqrtPriceX96);

        uint24 fee = uint24(
            s_feeManager.getFee(PoolId.unwrap(poolId), currentTick)
        );

        poolManager.updateDynamicLPFee(_poolKey, fee);
        uint24 feeWithFlag = fee | LPFeeLibrary.OVERRIDE_FEE_FLAG;

        uint128 liquidity = poolManager.getLiquidity(poolId);
        uint160 nextSqrtPriceX96 = currentSqrtPriceX96
            .getNextSqrtPriceFromInput(
                liquidity,
                uint256(_params.amountSpecified),
                _params.zeroForOne
            );

        int24 nextTick = TickMath.getTickAtSqrtPrice(nextSqrtPriceX96);

        s_dynamicShieldAVS.notifyTickEvent(PoolId.unwrap(poolId), nextTick);

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
    ) external override(BaseHook, IHooks) returns (bytes4, int128) {
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

        s_feeManager.updateFeePerTick(
            PoolId.unwrap(poolId),
            liquidity,
            int32(info.tickLower()),
            int32(info.tickUpper()),
            uint32(uint24(poolKey.tickSpacing)),
            uint32(s_feeInit),
            uint32(s_feeMax)
        );

        s_shieldInfos[poolId] = ShieldInfo({tokenId: _tokenId});

        IERC721(address(s_positionManager)).approve(
            address(s_vaultManager),
            _tokenId
        );
        s_vaultManager.depositPosition(poolKey, _tokenId, _from);

        s_tokenIds[poolId].push(_tokenId);

        s_dynamicShieldAVS.notifyRegisterShield(
            PoolId.unwrap(poolId),
            info.tickLower(),
            info.tickUpper(),
            _tokenId
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
        (, PositionInfo info) = s_positionManager.getPoolAndPositionInfo(
            _tokenId
        );
        uint128 liquidity = s_positionManager.getPositionLiquidity(_tokenId);

        s_feeManager.updateFeePerTick(
            PoolId.unwrap(_poolKey.toId()),
            liquidity,
            int32(info.tickLower()),
            int32(info.tickUpper()),
            uint32(uint24(_poolKey.tickSpacing)),
            uint32(s_feeInit),
            uint32(s_feeMax)
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

        s_feeManager.updateFeePerTick(
            PoolId.unwrap(_poolKey.toId()),
            liquidity,
            int32(info.tickLower()),
            int32(info.tickUpper()),
            uint32(uint24(_poolKey.tickSpacing)),
            uint32(s_feeInit),
            uint32(s_feeMax)
        );
    }

    function removeLiquidityInBatch(
        PoolId _poolId,
        uint256[] memory _tokenIds
    ) external onlyAVS {
        s_vaultManager.removeLiquidityInBatch(_poolId, _tokenIds);
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
}
