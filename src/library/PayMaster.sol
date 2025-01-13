// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {RatioMath} from "./RatioMath.sol";
import {Errors} from "../interfaces/Errors.sol";
import {UniswapV3Integration} from "./UniswapV3Integration.sol";
import {FullMath} from "./uniswap/FullMath.sol";
import {IWETH9} from "../interfaces/IWETH9.sol";
import {Storage} from "../storage/PoolPartyPositionStorage.sol";
import {IFeesVaultManager} from "../interfaces/IFeesVaultManager.sol";
import "../interfaces/Constants.sol";
import "../interfaces/IPoolPartyPosition.sol";

/**
 * @title PayMaster Library
 * @notice This library handles fee splitting, token transfers, and swaps for pool positions.
 */
library PayMaster {
    using SafeERC20 for ERC20;
    using PositionIdLib for PositionKey;

    /**
     * @notice Splits collected fees between the operator and the pool party.
     * @param _position The pool position.
     * @param _recipient The address to receive the collected fees.
     * @param _amountCurrency0 The amount of currency0 collected.
     * @param _amountCurrency1 The amount of currency1 collected.
     * @return recipientAmount0 The amount of currency0 received by the recipient.
     * @return recipientAmount1 The amount of currency1 received by the recipient.
     */
    function splitCollectedFees(
        IPoolPartyPosition _position,
        address _recipient,
        uint256 _amountCurrency0,
        uint256 _amountCurrency1
    ) external returns (uint256 recipientAmount0, uint256 recipientAmount1) {
        if (_amountCurrency0 == 0 && _amountCurrency1 == 0) {
            return (0, 0);
        }
        PositionKey memory positionKey = _position.poolPositionView().key();
        address operator = positionKey.operator;
        uint24 operatorFee = positionKey.operatorFee;
        uint24 protocolFee = _position.poolPositionView().protocolFee();
        address protocolFeeRecipient = _position
            .poolPositionView()
            .protocolFeeRecipient();
        address currency0 = positionKey.currency0;
        address currency1 = positionKey.currency1;

        uint256 operatorAmount0 = ((_amountCurrency0 * operatorFee) /
            FEE_DENOMINATOR);
        uint256 operatorAmount1 = ((_amountCurrency1 * operatorFee) /
            FEE_DENOMINATOR);
        //slither-disable-next-line divide-before-multiply
        uint256 poolPartyAmount0 = ((operatorAmount0 * protocolFee) /
            FEE_DENOMINATOR);
        //slither-disable-next-line divide-before-multiply
        uint256 poolPartyAmount1 = ((operatorAmount1 * protocolFee) /
            FEE_DENOMINATOR);

        recipientAmount0 = _amountCurrency0 - operatorAmount0;
        recipientAmount1 = _amountCurrency1 - operatorAmount1;
        operatorAmount0 -= poolPartyAmount0;
        operatorAmount1 -= poolPartyAmount1;

        if (_recipient == operator) {
            recipientAmount0 += operatorAmount0;
            recipientAmount1 += operatorAmount1;
        } else {
            _safeTransfer(_position, currency0, operator, operatorAmount0);
            _safeTransfer(_position, currency1, operator, operatorAmount1);
        }

        _safeTransfer(
            _position,
            currency0,
            protocolFeeRecipient,
            poolPartyAmount0
        );
        _safeTransfer(
            _position,
            currency1,
            protocolFeeRecipient,
            poolPartyAmount1
        );
        emit IPoolPartyPositionEvents.RewardsCollected(
            _recipient,
            positionKey.toId(),
            recipientAmount0,
            recipientAmount1
        );
    }

    /**
     * @notice Transfers tokens to the recipient, optionally swapping to StableCurrency.
     * @param _position The pool position.
     * @param _recipient The address to receive the tokens.
     * @param _amountCurrency0 The amount of currency0 to transfer.
     * @param _amountCurrency1 The amount of currency1 to transfer.
     * @param _swap The swap parameters.
     */
    function transferTokens(
        IPoolPartyPosition _position,
        address _recipient,
        uint256 _amountCurrency0,
        uint256 _amountCurrency1,
        IPoolPartyPositionStructs.SwapParams calldata _swap
    ) external {
        PositionKey memory positionKey = _position.poolPositionView().key();
        address currency0 = positionKey.currency0;
        address currency1 = positionKey.currency1;

        if (_swap.shouldSwapFees) {
            // slither-disable-next-line unused-return
            // aderyn-ignore-next-line
            swapToStableCurrency(
                _position,
                currency0,
                _swap.multihopSwapPath0,
                _amountCurrency0,
                _recipient,
                _swap.amount0OutMinimum
            );
            // slither-disable-next-line unused-return
            // aderyn-ignore-next-line
            swapToStableCurrency(
                _position,
                currency1,
                _swap.multihopSwapPath1,
                _amountCurrency1,
                _recipient,
                _swap.amount1OutMinimum
            );
        } else {
            _safeTransfer(_position, currency0, _recipient, _amountCurrency0);
            _safeTransfer(_position, currency1, _recipient, _amountCurrency1);
        }
    }

    /**
     * @notice Splits collected fees in StableCurrency between the operator and the pool party.
     * @param _position The pool position.
     * @param _recipient The address to receive the collected fees.
     * @param _amountStableCurrency The amount of StableCurrency collected.
     * @return recipientAmount The amount of StableCurrency received by the recipient.
     */
    function splitCollectedFeesInStableCurrency(
        IPoolPartyPosition _position,
        address _recipient,
        uint256 _amountStableCurrency
    ) external returns (uint256 recipientAmount) {
        if (_amountStableCurrency == 0) {
            return 0;
        }
        PositionKey memory positionKey = _position.poolPositionView().key();
        address operator = positionKey.operator;
        uint24 operatorFee = positionKey.operatorFee;
        uint24 protocolFee = _position.poolPositionView().protocolFee();
        address protocolFeeRecipient = _position
            .poolPositionView()
            .protocolFeeRecipient();

        uint256 operatorAmount = FullMath.mulDiv(
            _amountStableCurrency,
            operatorFee,
            FEE_DENOMINATOR
        );
        uint256 poolPartyAmount = FullMath.mulDiv(
            operatorAmount,
            protocolFee,
            FEE_DENOMINATOR
        );

        recipientAmount = _amountStableCurrency - operatorAmount;
        operatorAmount -= poolPartyAmount;

        if (_recipient == operator) {
            recipientAmount += operatorAmount;
        } else {
            transferStableCurrency(_position, operator, operatorAmount);
        }

        transferStableCurrency(
            _position,
            protocolFeeRecipient,
            poolPartyAmount
        );

        emit IPoolPartyPositionEvents.RewardsCollectedInStableCurrency(
            _recipient,
            positionKey.toId(),
            recipientAmount
        );
    }

    /**
     * @notice Transfers StableCurrency to the recipient.
     * @param _position The pool position.
     * @param _recipient The address to receive the StableCurrency.
     * @param _amountStableCurrency The amount of StableCurrency to transfer.
     */
    function transferStableCurrency(
        IPoolPartyPosition _position,
        address _recipient,
        uint256 _amountStableCurrency
    ) public {
        if (_amountStableCurrency == 0) {
            return;
        }
        ERC20(_position.poolPositionView().stableCurrency()).safeTransfer(
            _recipient,
            _amountStableCurrency
        );
    }

    /**
     * @notice Swaps tokens using Uniswap V3.
     * @param _position The pool position.
     * @param _tokenIn The token to swap from.
     * @param _tokenOut The token to swap to.
     * @param _path The swap path.
     * @param _amountIn The amount of token to swap.
     * @param _recipient The address to receive the swapped tokens.
     * @param _amountOutMinimum The minimum amount of token to receive.
     * @return amountOut The amount of token received.
     */
    function swap(
        IPoolPartyPosition _position,
        address _tokenIn,
        address _tokenOut,
        bytes memory _path,
        uint256 _amountIn,
        address _recipient,
        uint256 _amountOutMinimum
    ) public returns (uint256 amountOut) {
        if (_amountIn == 0) {
            return 0;
        }
        if (_tokenIn == _tokenOut) {
            ERC20(_tokenIn).safeTransfer(_recipient, _amountIn);
            return _amountIn;
        }

        return
            UniswapV3Integration.exactInputMultihopSwap({
                _swapRouter: _position.poolPositionView().swapRouter(),
                _tokenIn: _tokenIn,
                _path: _path,
                _recipient: _recipient,
                _amountIn: _amountIn,
                _amountOutMinimum: _amountOutMinimum
            });
    }

    function swapWithProtocolFee(
        IPoolPartyPosition _position,
        address _tokenIn,
        address _tokenOut,
        bytes memory _path,
        uint256 _amountIn,
        address _recipient,
        uint256 _amountOutMinimum
    ) external returns (uint256 amountOut) {
        if (_tokenOut != _tokenIn) {
            _amountIn = _protocolSwapFeePayment(_position, _tokenIn, _amountIn);
            _amountOutMinimum = _calcProtocolSwapFee(_amountOutMinimum);
        }
        return
            swap(
                _position,
                _tokenIn,
                _tokenOut,
                _path,
                _amountIn,
                _recipient,
                _amountOutMinimum
            );
    }

    /**
     * @notice Swaps StableCurrency to another token using Uniswap V3.
     * @param _position The pool position.
     * @param _tokenOut The token to swap to.
     * @param _path The swap path.
     * @param _amountIn The amount of StableCurrency to swap.
     * @param _recipient The address to receive the swapped tokens.
     * @param _amountOutMinimum The minimum amount of token to receive.
     * @return amountOut The amount of token received.
     */
    function swapFromStableCurrency(
        IPoolPartyPosition _position,
        address _tokenOut,
        bytes memory _path,
        uint256 _amountIn,
        address _recipient,
        uint256 _amountOutMinimum
    ) external returns (uint256 amountOut) {
        address stableCurrency = _position.poolPositionView().stableCurrency();
        if (_tokenOut != stableCurrency) {
            _amountIn = _protocolSwapFeePayment(
                _position,
                stableCurrency,
                _amountIn
            );
            _amountOutMinimum = _calcProtocolSwapFee(_amountOutMinimum);
        }
        return
            swap(
                _position,
                stableCurrency,
                _tokenOut,
                _path,
                _amountIn,
                _recipient,
                _amountOutMinimum
            );
    }

    /**
     * @notice Swaps a token to StableCurrency using Uniswap V3.
     * @param _position The pool position.
     * @param _tokenIn The token to swap from.
     * @param _path The swap path.
     * @param _amountIn The amount of token to swap.
     * @param _recipient The address to receive the swapped StableCurrency.
     * @param _amountOutMinimum The minimum amount of StableCurrency to receive.
     * @return amountOut The amount of StableCurrency received.
     */
    function swapToStableCurrency(
        IPoolPartyPosition _position,
        address _tokenIn,
        bytes memory _path,
        uint256 _amountIn,
        address _recipient,
        uint256 _amountOutMinimum
    ) public returns (uint256 amountOut) {
        address stableCurrency = _position.poolPositionView().stableCurrency();
        if (_tokenIn != stableCurrency) {
            _amountIn = _protocolSwapFeePayment(_position, _tokenIn, _amountIn);
            _amountOutMinimum = _calcProtocolSwapFee(_amountOutMinimum);
        }
        return
            swap(
                _position,
                _tokenIn,
                stableCurrency,
                _path,
                _amountIn,
                _recipient,
                _amountOutMinimum
            );
    }

    /**
     * @notice Withdraws remaining tokens from a closed position.
     * @param _position The pool position.
     */
    function withdrawRemainingTokens(
        Storage storage s,
        IPoolPartyPosition _position
    ) external {
        if (s.remainingLiquidityAfterClose > 0) {
            revert Errors.PoolPositionHasYetLiquidityAfterClose();
        }

        PositionKey memory positionKey = s.positionKey;
        address currency0 = positionKey.currency0;
        address currency1 = positionKey.currency1;

        (uint256 fees0, uint256 fees1, uint256 feesInStable) = _position
            .poolPositionView()
            .totalFeesInVault();
        IFeesVaultManager(s.i_feesVaultManager).withdraw(fees0, fees1);
        address protocolFeeRecipient = _position
            .poolPositionView()
            .protocolFeeRecipient();
        _safeTransfer(
            _position,
            currency0,
            protocolFeeRecipient,
            ERC20(currency0).balanceOf(address(_position))
        );
        _safeTransfer(
            _position,
            currency1,
            protocolFeeRecipient,
            ERC20(currency1).balanceOf(address(_position))
        );
        if (
            currency0 != s.i_stableCurrency && currency1 != s.i_stableCurrency
        ) {
            IFeesVaultManager(s.i_feesVaultManager).withdrawInStableCurrency(
                feesInStable
            );
            _safeTransfer(
                _position,
                s.i_stableCurrency,
                protocolFeeRecipient,
                ERC20(s.i_stableCurrency).balanceOf(address(_position))
            );
        }
    }

    /**
     * @notice Refunds with the unwrapped WETH9 or token to the recipient address.
     * @param _position The pool position.
     * @param _token The token to refund.
     * @param _value The amount of token to refund.
     * @param _recipient The address to receive the refund.
     */
    // aderyn-ignore-next-line(useless-internal-function)
    function refundWithUnwrapedWETHOrToken(
        IPoolPartyPosition _position,
        address _token,
        uint256 _value,
        address _recipient
    ) internal {
        // slither-disable-next-line incorrect-equality
        if (_value == 0) {
            return;
        }
        address _WETH9 = _position.poolPositionView().WETH9();
        uint256 balanceWETH9 = IWETH9(_token).balanceOf(address(_position));
        if (_token == _WETH9 && balanceWETH9 >= _value) {
            IWETH9(_token).withdraw(_value);
            TransferHelper.safeTransferETH(_recipient, _value);
        } else {
            ERC20(_token).safeTransfer(_recipient, _value);
        }
    }

    /**
     * @notice Wraps ETH to WETH9 and deposits it to the contract, or transfers the token to the recipient address.
     * @param _position The pool position.
     * @param _token The token to wrap or transfer.
     * @param _value The amount of token to wrap or transfer.
     * @param _recipient The address to receive the token.
     */
    function wrapETHOrTransferToken(
        IPoolPartyPosition _position,
        address _token,
        uint256 _value,
        address _recipient
    ) external {
        // slither-disable-next-line incorrect-equality
        if (_value == 0) {
            return;
        }
        address _WETH9 = _position.poolPositionView().WETH9();
        if (_token == _WETH9 && address(_position).balance >= _value) {
            // slither-disable-next-line arbitrary-send-eth
            IWETH9(_token).deposit{value: _value}();
        } else {
            ERC20(_token).safeTransferFrom(msg.sender, _recipient, _value);
        }
    }

    /**
     * @notice Computes the amounts of currency0 and currency1 from a given amount of StableCurrency.
     * @param positionKey The key of the pool position.
     * @param _amountStableCurrency The amount of StableCurrency.
     * @return amount0 The amount of currency0.
     * @return amount1 The amount of currency1.
     */
    function computeStableCurrencyToPairTokenAmounts(
        PositionKey memory positionKey,
        uint256 _amountStableCurrency
    ) external view returns (uint256 amount0, uint256 amount1) {
        //slither-disable-next-line unused-return
        (uint160 sqrtPriceX96Pool, , , , , , ) = IUniswapV3Pool(
            positionKey.pool
        ).slot0();

        uint256 ratio = RatioMath.ratio(positionKey, sqrtPriceX96Pool, false);

        /// @dev 10_000 is used to convert the ratio to a percentage with 4 decimals of precision
        amount0 = (_amountStableCurrency * ratio) / 10e3;
        amount1 = _amountStableCurrency - amount0;
    }

    /**
     * @notice Computes the minimum amount out from a given amount in, accounting for slippage.
     * @param _amountIn The amount in.
     * @return minAmountOut The minimum amount out.
     */
    function computeMinAmount(
        uint256 _amountIn
    ) external pure returns (uint256 minAmountOut) {
        /// @dev 2750 is 2,75%, then the max slippage is 2,75% of the amountIn
        // @dev we add 0.25% to the slippage to account for the pool party fee
        uint256 slippageAmount = ((_amountIn * 2750) / 100e3);
        minAmountOut = _amountIn - slippageAmount;
    }

    /**
     * @notice Safely transfers tokens, refunding with unwrapped WETH9 or token if necessary.
     * @param _position The view of the pool position.
     * @param _token The token to transfer.
     * @param _to The address to receive the token.
     * @param _amount The amount of token to transfer.
     */
    function _safeTransfer(
        IPoolPartyPosition _position,
        address _token,
        address _to,
        uint256 _amount
    ) internal {
        refundWithUnwrapedWETHOrToken(_position, _token, _amount, _to);
    }

    /**
     * @notice Calculates the pool party swap fee for a given amount.
     * @param _amountIn The amount in.
     * @return The calculated fee.
     */
    function _calcProtocolSwapFee(
        uint256 _amountIn
    ) internal pure returns (uint256) {
        if (_amountIn == 0) {
            return 0;
        }
        uint256 amount = (_amountIn * SWAP_FEE) / FEE_DENOMINATOR;
        return amount;
    }

    /**
     * @notice Processes the pool party swap fee payment.
     * @param _position The pool position.
     * @param _tokenIn The token to swap from.
     * @param _amountIn The amount of token to swap.
     * @return The amount after fee deduction.
     */
    function _protocolSwapFeePayment(
        IPoolPartyPosition _position,
        address _tokenIn,
        uint256 _amountIn
    ) internal returns (uint256) {
        if (_amountIn == 0) {
            return 0;
        }
        uint256 amount = _calcProtocolSwapFee(_amountIn);
        uint256 poolPartyAmount = _amountIn - amount;
        if (poolPartyAmount > 0) {
            _safeTransfer(
                _position,
                _tokenIn,
                _position.poolPositionView().protocolFeeRecipient(),
                poolPartyAmount
            );
        }
        return amount;
    }

    /**
     * @notice Checks if two byte arrays are equal.
     * @param a The first byte array.
     * @param b The second byte array.
     * @return True if the byte arrays are equal, false otherwise.
     */
    function _isBytesEqual(
        bytes memory a,
        bytes memory b
    ) internal pure returns (bool) {
        return keccak256(a) == keccak256(b);
    }

    /**
     * @notice Validates the multihop swap path.
     * @param multihopSwapPath The multihop swap path.
     * @return True if the swap path is valid, false otherwise.
     */
    function _isValidMultihopSwapPath(
        bytes memory multihopSwapPath
    ) external pure returns (bool) {
        return
            multihopSwapPath.length > 0 &&
            !_isBytesEqual(multihopSwapPath, bytes("0x00"));
    }
}
