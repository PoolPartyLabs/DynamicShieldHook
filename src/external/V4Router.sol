// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "forge-std/interfaces/IERC20.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {SafeCast} from "@uniswap/v4-core/src/libraries/SafeCast.sol";
import {Position} from "@uniswap/v4-core/src/libraries/Position.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {TransientStateLibrary} from "@uniswap/v4-core/src/libraries/TransientStateLibrary.sol";

import {PathKey, PathKeyLibrary} from "v4-periphery/src/libraries/PathKey.sol";
import {IV4Router} from "v4-periphery/src/interfaces/IV4Router.sol";
// import {BaseActionsRouter} from "v4-periphery/src/base/BaseActionsRouter.sol";
// import {DeltaResolver} from "v4-periphery/src/base/DeltaResolver.sol";
import {Actions} from "v4-periphery/src/libraries/Actions.sol";
import {ActionConstants} from "v4-periphery/src/libraries/ActionConstants.sol";
import {BipsLibrary} from "v4-periphery/src/libraries/BipsLibrary.sol";
import {LiquidityAmounts} from "v4-periphery/src/libraries/LiquidityAmounts.sol";
import {PositionInfo, PositionInfoLibrary} from "v4-periphery/src/libraries/PositionInfoLibrary.sol";
import {CalldataDecoder} from "v4-periphery/src/libraries/CalldataDecoder.sol";
import {SlippageCheck} from "v4-periphery/src/libraries/SlippageCheck.sol";

import {BaseActionsRouter} from "./base/BaseActionsRouter.sol";
import {DeltaResolver} from "./base/DeltaResolver.sol";

/// @title UniswapV4Router
/// @notice Abstract contract that contains all internal logic needed for routing through Uniswap v4 pools
/// @dev the entry point to executing actions in this contract is calling `BaseActionsRouter._executeActions`
/// An inheriting contract should call _executeActions at the point that they wish actions to be executed
abstract contract V4Router is IV4Router, DeltaResolver {
    using StateLibrary for IPoolManager;
    using TransientStateLibrary for IPoolManager;
    using SafeCast for *;
    using SafeCast for uint256;
    using SafeCast for int256;
    using SlippageCheck for BalanceDelta;
    using PathKeyLibrary for PathKey;
    using CalldataDecoder for bytes;
    using BipsLibrary for uint256;
    using PositionInfoLibrary for PositionInfo;

    error InputLengthMismatch();
    error UnsupportedAction(uint256 action);

    constructor(IPoolManager _poolManager) DeltaResolver(_poolManager) {}

    /// @notice internal function that triggers the execution of a set of actions on v4
    /// @dev inheriting contracts should call this function to trigger execution
    function _executeActions(bytes memory unlockData) internal {
        poolManager.unlock(unlockData);
    }

    function _unlockCallbackSwapRouter(
        bytes memory data
    ) internal returns (bytes memory) {
        // abi.decode(data, (bytes, bytes[]));
        (bytes memory actions, bytes[] memory params) = abi.decode(
            data,
            (bytes, bytes[])
        );
        _executeActionsWithoutUnlock(actions, params);
        return "";
    }

    function _executeActionsWithoutUnlock(
        bytes memory actions,
        bytes[] memory params
    ) internal {
        uint256 numActions = actions.length;
        if (numActions != params.length) revert InputLengthMismatch();

        for (uint256 actionIndex = 0; actionIndex < numActions; actionIndex++) {
            uint256 action = uint8(actions[actionIndex]);

            _handleAction(action, params[actionIndex]);
        }
    }

    function _handleAction(uint256 action, bytes memory params) internal {
        // swap actions and payment actions in different blocks for gas efficiency
        if (action < Actions.SETTLE) {
            if (action == Actions.SWAP_EXACT_IN_SINGLE) {
                IV4Router.ExactInputSingleParams memory swapParams = abi.decode(
                    params,
                    (IV4Router.ExactInputSingleParams)
                );
                _swapExactInputSingle(swapParams);
                return;
            }
        } else {
            if (action == Actions.SETTLE_ALL) {
                (Currency currency, uint256 maxAmount) = abi.decode(
                    params,
                    (Currency, uint256)
                );
                uint256 amount = _getFullDebt(currency);
                if (amount > maxAmount)
                    revert V4TooMuchRequested(maxAmount, amount);
                _settle(currency, msgSender(), amount);
                return;
            } else if (action == Actions.TAKE_ALL) {
                (Currency currency, uint256 minAmount) = abi.decode(
                    params,
                    (Currency, uint256)
                );
                uint256 amount = _getFullCredit(currency);
                if (amount < minAmount)
                    revert V4TooLittleReceived(minAmount, amount);
                _take(currency, msgSender(), amount);
                return;
            } else if (action == Actions.SETTLE) {
                (Currency currency, uint256 amount, bool payerIsUser) = abi
                    .decode(params, (Currency, uint256, bool));
                _settle(
                    currency,
                    _mapPayer(payerIsUser),
                    _mapSettleAmount(amount, currency)
                );
                return;
            } else if (action == Actions.TAKE) {
                (Currency currency, address recipient, uint256 amount) = abi
                    .decode(params, (Currency, address, uint256));
                _take(
                    currency,
                    _mapRecipient(recipient),
                    _mapTakeAmount(amount, currency)
                );
                return;
            } else if (action == Actions.TAKE_PORTION) {
                (Currency currency, address recipient, uint256 bips) = abi
                    .decode(params, (Currency, address, uint256));
                _take(
                    currency,
                    _mapRecipient(recipient),
                    _getFullCredit(currency).calculatePortion(bips)
                );
                return;
            }
        }
        revert UnsupportedAction(action);
    }

    function _swapExactInputSingle(
        IV4Router.ExactInputSingleParams memory params
    ) private {
        uint128 amountIn = params.amountIn;
        if (amountIn == ActionConstants.OPEN_DELTA) {
            amountIn = _getFullCredit(
                params.zeroForOne
                    ? params.poolKey.currency0
                    : params.poolKey.currency1
            ).toUint128();
        }
        uint128 amountOut = _swap(
            params.poolKey,
            params.zeroForOne,
            -int256(uint256(amountIn)),
            params.hookData
        ).toUint128();
        if (amountOut < params.amountOutMinimum)
            revert V4TooLittleReceived(params.amountOutMinimum, amountOut);
    }

    function _swapExactInput(
        IV4Router.ExactInputParams calldata params
    ) private {
        unchecked {
            // Caching for gas savings
            uint256 pathLength = params.path.length;
            uint128 amountOut;
            Currency currencyIn = params.currencyIn;
            uint128 amountIn = params.amountIn;
            if (amountIn == ActionConstants.OPEN_DELTA)
                amountIn = _getFullCredit(currencyIn).toUint128();
            PathKey calldata pathKey;

            for (uint256 i = 0; i < pathLength; i++) {
                pathKey = params.path[i];
                (PoolKey memory poolKey, bool zeroForOne) = pathKey
                    .getPoolAndSwapDirection(currencyIn);
                // The output delta will always be positive, except for when interacting with certain hook pools
                amountOut = _swap(
                    poolKey,
                    zeroForOne,
                    -int256(uint256(amountIn)),
                    pathKey.hookData
                ).toUint128();

                amountIn = amountOut;
                currencyIn = pathKey.intermediateCurrency;
            }

            if (amountOut < params.amountOutMinimum)
                revert V4TooLittleReceived(params.amountOutMinimum, amountOut);
        }
    }

    function _swap(
        PoolKey memory poolKey,
        bool zeroForOne,
        int256 amountSpecified,
        bytes memory hookData
    ) private returns (int128 reciprocalAmount) {
        // for protection of exactOut swaps, sqrtPriceLimit is not exposed as a feature in this contract
        unchecked {
            BalanceDelta delta = poolManager.swap(
                poolKey,
                IPoolManager.SwapParams(
                    zeroForOne,
                    amountSpecified,
                    zeroForOne
                        ? TickMath.MIN_SQRT_PRICE + 1
                        : TickMath.MAX_SQRT_PRICE - 1
                ),
                hookData
            );

            reciprocalAmount = (zeroForOne == amountSpecified < 0)
                ? delta.amount1()
                : delta.amount0();
        }
    }

    function msgSender() public view virtual returns (address);

    /// @notice Calculates the address for a action
    function _mapRecipient(address recipient) internal view returns (address) {
        if (recipient == ActionConstants.MSG_SENDER) {
            return msgSender();
        } else if (recipient == ActionConstants.ADDRESS_THIS) {
            return address(this);
        } else {
            return recipient;
        }
    }

    /// @notice Calculates the payer for an action
    function _mapPayer(bool payerIsUser) internal view returns (address) {
        return payerIsUser ? msgSender() : address(this);
    }
}
