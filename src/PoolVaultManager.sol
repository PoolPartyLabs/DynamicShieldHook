// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

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

import {console} from "forge-std/Test.sol";

bytes constant ZERO_BYTES = new bytes(0);

contract PoolVaultManager is V4Router, Ownable {
    using PoolIdLibrary for PoolKey;
    using Planner for Plan;
    using StateLibrary for IPoolManager;
    using PositionInfoLibrary for PositionInfo;
    using CurrencyLibrary for Currency;
    using SafeTransferLib for *;
    using CalldataDecoder for bytes;

    struct Position {
        PoolKey key;
        address owner;
        uint256 tokenId;
    }

    struct PositionTotalSupply {
        PoolKey key;
        uint256 tokenId;
        uint256 amount0;
        uint256 amount1;
    }

    struct CallData {
        PoolKey key;
        address owner;
    }

    IPositionManager private s_lpm;
    IAllowanceTransfer private s_permit2;
    Currency private s_safeToken;
    mapping(uint256 tokenId => Position) private s_postions;
    mapping(PoolId => PoolKey) private s_poolKeys;

    error InvalidPositionManager();
    error InvalidHook();
    error InvalidSelf();

    constructor(
        IPoolManager _pm,
        IPositionManager _lpm,
        IAllowanceTransfer _permit2,
        Currency _safeToken,
        address _hook
    ) V4Router(_pm) Ownable(_hook) {
        s_lpm = _lpm;
        s_permit2 = _permit2;
        s_safeToken = _safeToken;
    }

    function depositPosition(
        PoolKey calldata _key,
        uint256 _tokenId,
        address _owner
    ) external payable onlyOwner {
        IERC721(address(s_lpm)).safeTransferFrom(
            msg.sender,
            address(this),
            _tokenId,
            abi.encode(CallData({key: _key, owner: _owner}))
        );
    }

    function onERC721Received(
        address _operator,
        address _from,
        uint256 _tokenId,
        bytes calldata _data
    ) external returns (bytes4) {
        // Check if the sender is the hook
        if (msg.sender != address(s_lpm)) revert InvalidPositionManager();
        if (_from != owner()) revert InvalidHook();
        if (_operator != address(this)) revert InvalidSelf();

        CallData memory data = abi.decode(_data, (CallData));
        s_postions[_tokenId] = Position(data.key, data.owner, _tokenId);
        s_poolKeys[data.key.toId()] = data.key;

        return this.onERC721Received.selector;
    }

    function mint() external {
        // @todo
    }

    function addLiquidity(
        PoolKey memory _key,
        uint256 _tokenId,
        uint256 _amount0,
        uint256 _amount1,
        uint256 _deadline
    ) external onlyOwner {
        IERC20(Currency.unwrap(_key.currency0)).transferFrom(
            msg.sender,
            address(this),
            _amount0
        );
        IERC20(Currency.unwrap(_key.currency1)).transferFrom(
            msg.sender,
            address(this),
            _amount1
        );

        _approvePosmCurrency(_key.currency0, _amount0);
        _approvePosmCurrency(_key.currency1, _amount1);
        Plan memory planner = Planner.init();
        (uint160 sqrtPriceX96, , , ) = poolManager.getSlot0(_key.toId());
        (, PositionInfo info) = s_lpm.getPoolAndPositionInfo(_tokenId);
        uint128 newLiquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(info.tickLower()),
            TickMath.getSqrtPriceAtTick(info.tickUpper()),
            _amount0,
            _amount1
        );
        planner.add(
            Actions.INCREASE_LIQUIDITY,
            // @todo should inform maxAmount0 and maxAmount1 to prevent slippage
            abi.encode(_tokenId, newLiquidity, _amount0, _amount1, ZERO_BYTES)
        );
        planner.finalizeModifyLiquidityWithClose(_key);

        bytes memory actions = planner.encode();

        s_lpm.modifyLiquidities(actions, _deadline);
    }

    function removeLiquidity(
        PoolKey memory _key,
        uint256 _tokenId,
        uint128 _percentage,
        uint256 _deadline
    ) external onlyOwner {
        require(_percentage > 0 && _percentage <= 100e4, "Invalid percentage");

        (uint256 amount0, uint256 amount1) = _removeLiquidity(
            _key,
            _tokenId,
            _percentage,
            _deadline,
            false
        );

        Position memory position = s_postions[_tokenId];

        _key.currency0.transfer(position.owner, amount0);
        _key.currency1.transfer(position.owner, amount1);
    }

    function collectFees(
        PoolKey memory _key,
        uint256 _tokenId,
        uint256 _deadline
    ) external onlyOwner {
        uint256 beforeBalance0 = _key.currency0.balanceOfSelf();
        uint256 beforeBalance1 = _key.currency1.balanceOfSelf();

        Plan memory planner = Planner.init();
        planner.add(
            Actions.DECREASE_LIQUIDITY,
            abi.encode(_tokenId, 0, 0, 0, ZERO_BYTES)
        );
        planner.finalizeModifyLiquidityWithClose(_key);

        bytes memory actions = planner.encode();

        s_lpm.modifyLiquidities(actions, _deadline);
        uint256 afterBalance0 = _key.currency0.balanceOfSelf();
        uint256 afterBalance1 = _key.currency1.balanceOfSelf();

        uint256 fees0 = afterBalance0 - beforeBalance0;
        uint256 fees1 = afterBalance1 - beforeBalance1;

        Position memory position = s_postions[_tokenId];
        _key.currency0.transfer(position.owner, fees0);
        _key.currency1.transfer(position.owner, fees1);
    }

    function removeLiquidityInBatch(
        PoolId poolId,
        uint256[] calldata _tokenIds
    ) external {
        uint256 tokenIdsLength = _tokenIds.length;
        require(tokenIdsLength <= 500, "Too many tokenIds");
        PoolKey memory poolKey = s_poolKeys[poolId];
        for (uint256 i = 0; i < tokenIdsLength; i++) {
            uint256 tonekId = _tokenIds[i];
            (uint256 amount0, uint256 amount1) = _removeLiquidity(
                poolKey,
                tonekId,
                99e4, // 99%
                0,
                true
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
            uint128 liquidity = s_lpm.getPositionLiquidity(tokenId);
            (uint160 sqrtPriceX96, , , ) = poolManager.getSlot0(_key.toId());
            (, PositionInfo info) = s_lpm.getPoolAndPositionInfo(tokenId);

            (uint256 amount0, uint256 amount1) = LiquidityAmounts
                .getAmountsForLiquidity(
                    sqrtPriceX96,
                    TickMath.getSqrtPriceAtTick(info.tickLower()),
                    TickMath.getSqrtPriceAtTick(info.tickUpper()),
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

    function msgSender() public view virtual override returns (address) {
        return address(this);
    }

    function _approvePosmCurrency(Currency _currency, uint256 _amount) private {
        // Because POSM uses permit2, we must execute 2 permits/approvals.
        // 1. First, the caller must approve permit2 on the token.
        IERC20(Currency.unwrap(_currency)).approve(address(s_permit2), _amount);
        // 2. Then, the caller must approve POSM as a spender of permit2. TODO: This could also be a signature.
        s_permit2.approve(
            Currency.unwrap(_currency),
            address(s_lpm),
            uint160(_amount),
            type(uint48).max
        );
    }

    function _removeLiquidity(
        PoolKey memory _key,
        uint256 _tokenId,
        uint128 _percentage,
        uint256 _deadline,
        bool _withoutUnlock
    ) private returns (uint256 amount0, uint256 amount1) {
        uint128 liquidity = s_lpm.getPositionLiquidity(_tokenId);
        (uint160 sqrtPriceX96, , , ) = poolManager.getSlot0(_key.toId());
        uint128 liquidityToRemove = uint128((liquidity * _percentage) / 100e4);
        (, PositionInfo info) = s_lpm.getPoolAndPositionInfo(_tokenId);

        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(info.tickLower()),
            TickMath.getSqrtPriceAtTick(info.tickUpper()),
            liquidityToRemove
        );
        Plan memory planner = Planner.init();
        planner.add(
            Actions.DECREASE_LIQUIDITY,
            // @todo should inform minAmount0 and minAmount1 to prevent slippage
            abi.encode(_tokenId, liquidityToRemove, 0, 0, ZERO_BYTES)
        );
        planner.finalizeModifyLiquidityWithClose(_key);

        bytes memory plan = planner.encode();
        if (_withoutUnlock) {
            (bytes memory actions, bytes[] memory params) = abi.decode(
                plan,
                (bytes, bytes[])
            );

            s_lpm.modifyLiquiditiesWithoutUnlock(actions, params);
        } else {
            s_lpm.modifyLiquidities(plan, _deadline);
        }
    }

    function _swapToSafeToken(
        Currency _currencyIn,
        uint256 _tokenId,
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

        bool zeroForOne = true;

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

        (bytes memory actions, bytes[] memory _params) = abi.decode(
            data,
            (bytes, bytes[])
        );
        _executeActionsWithoutUnlock(actions, _params);
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
