// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

/** OpenZeppelin Contracts */
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/** Solmate */
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

/** Forge */
import {IERC721} from "forge-std/interfaces/IERC721.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

/** Uniswap v4 Core */
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";

/** Uniswap v4 Periphery */
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {PositionInfo, PositionInfoLibrary} from "v4-periphery/src/libraries/PositionInfoLibrary.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {Actions} from "v4-periphery/src/libraries/Actions.sol";
import {CalldataDecoder} from "v4-periphery/src/libraries/CalldataDecoder.sol";

/** Internal */
import {Planner, Plan} from "./library/external/Planner.sol";
import {LiquidityAmounts} from "./library/external/LiquidityAmounts.sol";
import {V4Router, IV4Router} from "./external/V4Router.sol";
import {IPoolVaultManager} from "./interfaces/IPoolVaultManager.sol";
import {PoolModifyLiquidity} from "./external/PoolModifyLiquidity.sol";

bytes constant ZERO_BYTES = new bytes(0);

contract PoolVaultManager is
    IPoolVaultManager,
    PoolModifyLiquidity,
    V4Router,
    Ownable
{
    using PoolIdLibrary for PoolKey;
    using Planner for Plan;
    using StateLibrary for IPoolManager;
    using PositionInfoLibrary for PositionInfo;
    using CurrencyLibrary for Currency;
    using SafeTransferLib for *;
    using CalldataDecoder for bytes;

    Currency private s_safeToken;
    mapping(PoolId => PoolKey) private s_poolKeys;

    constructor(
        IPoolManager _pm,
        Currency _safeToken,
        address _hook
    ) PoolModifyLiquidity(_pm) V4Router(_pm) Ownable(_hook) {
        s_safeToken = _safeToken;
    }

    function mint(
        PoolKey calldata _poolKey,
        IPoolManager.ModifyLiquidityParams memory _params,
        address _owner,
        uint256 _amount0Desired,
        uint256 _amount1Desired
    ) external returns (uint256 tokenId) {
        IERC20(Currency.unwrap(_poolKey.currency0)).transferFrom(
            msg.sender,
            address(this),
            _amount0Desired
        );
        IERC20(Currency.unwrap(_poolKey.currency1)).transferFrom(
            msg.sender,
            address(this),
            _amount1Desired
        );

        IERC20(Currency.unwrap(_poolKey.currency0)).approve(
            address(poolManager),
            _amount0Desired
        );
        IERC20(Currency.unwrap(_poolKey.currency1)).approve(
            address(poolManager),
            _amount1Desired
        );

        tokenId = nextTokenId;
        s_poolKeys[_poolKey.toId()] = _poolKey;
        mintAndAddLiquidity(_poolKey, _params, _owner, bytes(""));
    }

    function addLiquidity(
        PoolKey memory _poolKey,
        uint256 _tokenId,
        address _owner,
        uint256 _amount0Desired,
        uint256 _amount1Desired
    ) external onlyOwner {
        IERC20(Currency.unwrap(_poolKey.currency0)).transferFrom(
            msg.sender,
            address(this),
            _amount0Desired
        );
        IERC20(Currency.unwrap(_poolKey.currency1)).transferFrom(
            msg.sender,
            address(this),
            _amount1Desired
        );

        IERC20(Currency.unwrap(_poolKey.currency0)).approve(
            address(poolManager),
            _amount0Desired
        );
        IERC20(Currency.unwrap(_poolKey.currency1)).approve(
            address(poolManager),
            _amount1Desired
        );

        PositionInfo memory info = positionInfo[_tokenId];
        s_poolKeys[_poolKey.toId()] = _poolKey;

        (uint160 sqrtPriceX96, , , ) = poolManager.getSlot0(_poolKey.toId());
        uint128 newLiquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(info.tickLower),
            TickMath.getSqrtPriceAtTick(info.tickUpper),
            _amount0Desired,
            _amount1Desired
        );
        modifyLiquidity(
            _poolKey,
            IPoolManager.ModifyLiquidityParams({
                tickLower: info.tickLower,
                tickUpper: info.tickUpper,
                liquidityDelta: int256(uint256(newLiquidity)),
                salt: bytes32("")
            }),
            _tokenId,
            _owner,
            bytes("")
        );
    }

    function removeLiquidity(
        PoolKey memory _poolKey,
        uint256 _tokenId,
        uint128 _percentage,
        address _owner
    ) external onlyOwner returns (uint256 amount0, uint256 amount1) {
        PositionInfo memory position = positionInfo[_tokenId];
        require(position.owner == _owner, "Invalid owner");
        require(_percentage > 0 && _percentage <= 100e4, "Invalid percentage");

        (amount0, amount1) = _removeLiquidity(
            _poolKey,
            _tokenId,
            _percentage,
            false
        );
        _poolKey.currency0.transfer(_owner, amount0);
        _poolKey.currency1.transfer(_owner, amount1);
    }

    function collectFees(
        PoolKey memory _poolKey,
        uint256 _tokenId,
        address _owner
    ) external onlyOwner returns (uint256 fees0, uint256 fees1) {
        PositionInfo memory position = positionInfo[_tokenId];
        require(position.owner == _owner, "Invalid owner");
        uint256 beforeBalance0 = _poolKey.currency0.balanceOfSelf();
        uint256 beforeBalance1 = _poolKey.currency1.balanceOfSelf();

        _removeLiquidity(_poolKey, _tokenId, 100e4, false);

        uint256 afterBalance0 = _poolKey.currency0.balanceOfSelf();
        uint256 afterBalance1 = _poolKey.currency1.balanceOfSelf();

        fees0 = afterBalance0 - beforeBalance0;
        fees1 = afterBalance1 - beforeBalance1;
        _poolKey.currency0.transfer(_owner, fees0);
        _poolKey.currency1.transfer(_owner, fees1);
    }

    function removeLiquidityInBatch(
        PoolId,
        uint256[] calldata _tokenIds,
        bool _withoutUnlock
    ) external {
        uint256 tokenIdsLength = _tokenIds.length;
        require(tokenIdsLength <= 500, "Too many tokenIds");
        for (uint256 i = 0; i < tokenIdsLength; i++) {
            uint256 tonekId = _tokenIds[i];
            PoolKey memory poolKey = positionInfo[tonekId].key;

            (uint256 amount0, uint256 amount1) = _removeLiquidity(
                poolKey,
                tonekId,
                99e4, // 99%
                _withoutUnlock
            );
            _swapToSafeToken(
                poolKey.currency0,
                tonekId,
                amount0,
                address(this)
            );

            _swapToSafeToken(
                poolKey.currency1,
                tonekId,
                amount1,
                address(this)
            );
        }
    }

    function getTotalSupplies(
        PoolKey calldata _key,
        uint256[] calldata _tokenIds
    ) external view returns (PositionTotalSupply[] memory totalSupplies) {
        uint256 length = _tokenIds.length;
        require(length <= 500, "Too many tokenIds");
        totalSupplies = new PositionTotalSupply[](length);
        for (uint256 i = 0; i < length; i++) {
            uint256 tokenId = _tokenIds[i];
            uint128 liquidity = _getLiquidity(tokenId);
            (uint160 sqrtPriceX96, , , ) = poolManager.getSlot0(_key.toId());
            (, PositionInfo memory info) = getPoolAndPositionInfo(tokenId);
            (uint256 amount0, uint256 amount1) = LiquidityAmounts
                .getAmountsForLiquidity(
                    sqrtPriceX96,
                    TickMath.getSqrtPriceAtTick(info.tickLower),
                    TickMath.getSqrtPriceAtTick(info.tickUpper),
                    liquidity
                );
            totalSupplies[i] = PositionTotalSupply(
                _key,
                tokenId,
                amount0,
                amount1
            );
        }
    }

    function getPoolAndPositionInfo(
        uint256 _tokenId
    ) public view returns (PoolKey memory poolKey, PositionInfo memory info) {
        info = positionInfo[_tokenId];
        poolKey = info.key;
    }

    function getPositionLiquidity(
        uint256 _tokenId
    ) external view returns (uint128 liquidity) {
        liquidity = _getLiquidity(_tokenId);
    }

    function ownerOf(uint256 _tokenId) external view returns (address owner) {
        owner = positionInfo[_tokenId].owner;
    }

    function msgSender() public view virtual override returns (address) {
        return address(this);
    }

    // implementation of abstract function DeltaResolver._pay
    function _pay(
        Currency currency,
        address payer,
        uint256 amount
    ) internal override {
        if (payer == address(this)) {
            currency.transfer(address(poolManager), amount);
        } else {
            // Casting from uint256 to uint160 is safe due to limits on the total supply of a pool
            ERC20(Currency.unwrap(currency)).safeTransferFrom(
                payer,
                address(poolManager),
                uint160(amount)
            );
        }
    }

    function _removeLiquidity(
        PoolKey memory _key,
        uint256 _tokenId,
        uint128 _percentage,
        bool _withoutUnlock
    ) private returns (uint256 amount0, uint256 amount1) {
        (, PositionInfo memory info) = getPoolAndPositionInfo(_tokenId);
        uint128 liquidity = _getLiquidity(_tokenId);
        (uint160 sqrtPriceX96, , , ) = poolManager.getSlot0(_key.toId());
        uint128 liquidityToRemove = uint128((liquidity * _percentage) / 100e4);
        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(info.tickLower),
            TickMath.getSqrtPriceAtTick(info.tickUpper),
            liquidityToRemove
        );
        if (_withoutUnlock) {
            modifyLiquidityWithoutUnlock(
                _key,
                IPoolManager.ModifyLiquidityParams({
                    tickLower: info.tickLower,
                    tickUpper: info.tickUpper,
                    liquidityDelta: -int256(uint256(liquidityToRemove)),
                    salt: bytes32(_tokenId)
                }),
                _tokenId,
                info.owner,
                bytes("")
            );
            return (amount0, amount1);
        }
        modifyLiquidity(
            _key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: info.tickLower,
                tickUpper: info.tickUpper,
                liquidityDelta: -int256(uint256(liquidityToRemove)),
                salt: bytes32(_tokenId)
            }),
            _tokenId,
            info.owner,
            bytes("")
        );
    }

    function _swapToSafeToken(
        Currency _currencyIn,
        uint256,
        uint256 _amountIn,
        address _recipient
    ) private {
        // @todo should be removed in production and use multiple pathkeys
        PoolKey memory poolKeyCurrencyToUSDC = _poolKeyUnsorted(
            _currencyIn,
            s_safeToken,
            IHooks(address(0)),
            3000,
            60
        );
        bool zeroForOne = poolKeyCurrencyToUSDC.currency0 == _currencyIn;
        IERC20(Currency.unwrap(_currencyIn)).approve(
            address(poolManager),
            _amountIn
        );
        // @todo should be removed in production and use multi-hop swap
        IV4Router.ExactInputSingleParams memory params = IV4Router
            .ExactInputSingleParams(
                poolKeyCurrencyToUSDC,
                zeroForOne,
                uint128(_amountIn),
                0, // amountOutMinimum should not be zero in production to prevent slippage
                bytes("")
            );
        Plan memory planner = Planner.init();
        planner.add(Actions.SWAP_EXACT_IN_SINGLE, abi.encode(params));
        bytes memory data = planner.finalizeSwap(
            _currencyIn,
            s_safeToken,
            _recipient
        );
        _executeActions(abi.encode(CallbackUnlockData(false, data)));
    }

    function unlockCallback(
        bytes calldata data
    ) external onlyPoolManager returns (bytes memory) {
        CallbackUnlockData memory _data = abi.decode(data, (CallbackUnlockData));
        if (!_data.modifyLiquidity) {
            return _unlockCallbackSwapRouter(_data.unlockData);
        }
        return _unlockCallbackModifyLiquidity(_data.unlockData);
    }

    function _getLiquidity(
        uint256 tokenId
    ) internal view returns (uint128 liquidity) {
        liquidity = uint128(positionInfo[tokenId].liquidity);
    }

    function _poolKeyUnsorted(
        Currency currencyA,
        Currency currencyB,
        IHooks hooks,
        uint24 fee,
        int24 tickSpacing
    ) private pure returns (PoolKey memory poolKey) {
        Currency _currency0;
        Currency _currency1;
        if (Currency.unwrap(currencyA) < Currency.unwrap(currencyB)) {
            (_currency0, _currency1) = (currencyA, currencyB);
        } else {
            (_currency0, _currency1) = (currencyB, currencyA);
        }
        poolKey = PoolKey(_currency0, _currency1, fee, tickSpacing, hooks);
    }
}
