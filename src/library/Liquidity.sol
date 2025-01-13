// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {PayMaster} from "./PayMaster.sol";
import {UniswapV3Integration} from "./UniswapV3Integration.sol";
import {Rewards} from "./Rewards.sol";
import {Core} from "./Core.sol";
import {Storage} from "../storage/PoolPartyPositionStorage.sol";
import {ISnapshotManager, ISnapshotManagerStructs} from "../interfaces/ISnapshotManager.sol";
import {Errors} from "../interfaces/Errors.sol";
import {IFeesVaultManager} from "../interfaces/IFeesVaultManager.sol";
import {IRefundVaultManager} from "../interfaces/IRefundVaultManager.sol";
import "../interfaces/Constants.sol";
import "../interfaces/IPoolPartyPosition.sol";

/**
 * @title Liquidity Library
 * @notice This library provides functionalities for managing liquidity in Uniswap V3 pool positions,
 * including adding, updating, and refunding liquidity.
 */
library Liquidity {
    using PositionIdLib for PositionKey;
    using SafeERC20 for IERC20;

    /**
     * @notice Increases liquidity in a pool position.
     * @param s The storage reference for the pool position.
     * @param _position The view of the pool position.
     * @param _params The parameters required to increase the liquidity.
     * @return _liquidity The amount of liquidity added.
     * @return amount0 The amount of currency0 added.
     * @return amount1 The amount of currency1 added.
     */
    function increaseLiquidity(
        Storage storage s,
        IPoolPartyPosition _position,
        IPoolPartyPosition.IncreaseLiquidityParams calldata _params
    ) external returns (uint128 _liquidity, uint256 amount0, uint256 amount1) {
        PositionId positionId = s.positionKey.toId();

        require(
            !_position.poolPositionView().isClosed(),
            Errors.PoolPositionAlreadyClosed()
        );

        //slither-disable-next-line timestamp
        require(_params.deadline >= block.timestamp, Errors.ExpiredDeadline());
        require(
            _params.amount0StableCurrency > 0 ||
                _params.amount1StableCurrency > 0,
            Errors.StableCurrencyAmountCannotBeZero(
                _params.amount0StableCurrency,
                _params.amount1StableCurrency
            )
        );

        _checkMultihopSwapPathForIncrease(
            s,
            _params.swap,
            _params.amount0StableCurrency,
            _params.amount1StableCurrency
        );
        address investor = _params.investor;

        Core.syncInvestor(s, investor);
        updateLiquidity(s, _position);
        Rewards.updateRewardsOf(s, _position, investor, address(_position));

        uint256 amount0Desired = 0;
        uint256 amount1Desired = 0;
        if (_params.amount0StableCurrency > 0) {
            IERC20(s.i_stableCurrency).safeTransferFrom(
                msg.sender,
                address(_position),
                _params.amount0StableCurrency
            );

            amount0Desired = PayMaster.swapFromStableCurrency(
                _position,
                s.i_currency0,
                _params.swap.multihopSwapPath0,
                _params.amount0StableCurrency,
                address(_position),
                _params.swap.amount0OutMinimum
            );
        }
        if (_params.amount1StableCurrency > 0) {
            IERC20(s.i_stableCurrency).safeTransferFrom(
                msg.sender,
                address(_position),
                _params.amount1StableCurrency
            );

            amount1Desired = PayMaster.swapFromStableCurrency(
                _position,
                s.i_currency1,
                _params.swap.multihopSwapPath1,
                _params.amount1StableCurrency,
                address(_position),
                _params.swap.amount1OutMinimum
            );
        }

        IERC20(s.i_currency0).forceApprove(
            address(_position.poolPositionView().nonfungiblePositionManager()),
            amount0Desired
        );
        IERC20(s.i_currency1).forceApprove(
            address(_position.poolPositionView().nonfungiblePositionManager()),
            amount1Desired
        );

        (_liquidity, amount0, amount1) = UniswapV3Integration.increase({
            s: s,
            _amount0Desired: amount0Desired,
            _amount1Desired: amount1Desired,
            _amount0Min: _params.ignoreSlippage
                ? 0
                : PayMaster.computeMinAmount(amount0Desired),
            _amount1Min: _params.ignoreSlippage
                ? 0
                : PayMaster.computeMinAmount(amount1Desired),
            _deadline: _params.deadline
        });

        // slither-disable-next-line reentrancy-events
        emit IPoolPartyPositionEvents.LiquidityAdded(
            investor,
            positionId,
            _liquidity,
            amount0,
            amount1
        );

        try
            UniswapV3Integration.getAmountsFromLiquidity(_position, _liquidity)
        returns (uint256 _amount0, uint256 _amount1) {
            if (_amount0 > amount0 || _amount1 > amount1) {
                revert Errors.InvalidLiquidityAmounts();
            }
        } catch {
            revert Errors.InvalidLiquidityAmounts();
        }

        uint256 amount0Refund = amount0Desired > amount0
            ? amount0Desired - amount0
            : 0;
        uint256 amount1Refund = amount1Desired > amount1
            ? amount1Desired - amount1
            : 0;
        _refundFromIncrease(
            s,
            _position,
            _params.swap,
            investor,
            amount0Refund,
            amount1Refund
        );

        updateLiquidity(s, _position);
        s.uniswapLiquidityOf[investor] += _liquidity;
        s.liquidityOf[investor] = _calcAddLiquidity(
            s.liquidityOf[investor],
            amount0,
            amount1
        );
        s.liquidity = _calcAddLiquidity(s.liquidity, amount0, amount1);

        ISnapshotManager(s.i_snapshotManager).takeInvestorSnapshot(
            investor,
            s.liquidityOf[investor],
            s.earned0Of[investor],
            s.earned1Of[investor],
            s.rewardIndex0Of[investor],
            s.rewardIndex1Of[investor]
        );

        return (_liquidity, amount0, amount1);
    }

    /**
     * @notice Decreases liquidity in a pool position.
     * @param s The storage reference for the pool position.
     * @param _position The view of the pool position.
     * @param _params The parameters required to decrease the liquidity.
     * @return The amount of liquidity removed.
     * @return The amount of currency0 removed.
     * @return The amount of currency1 removed.
     */
    function decreaseLiquidity(
        Storage storage s,
        IPoolPartyPosition _position,
        IPoolPartyPosition.DecreaseLiquidityParams calldata _params
    ) external returns (uint128, uint256, uint256) {
        require(
            !_position.poolPositionView().isClosed(),
            Errors.PoolPositionAlreadyClosed()
        );
        //slither-disable-next-line timestamp
        require(_params.deadline >= block.timestamp, Errors.ExpiredDeadline());
        require(
            _params.percentage >= 1e15 && _params.percentage <= 100e15,
            Errors.InvalidRemovePercentage(_params.percentage)
        );
        if (
            _params.swap.shouldSwapFees &&
            !PayMaster._isValidMultihopSwapPath(
                _params.swap.multihopSwapPath0
            ) &&
            !PayMaster._isValidMultihopSwapPath(_params.swap.multihopSwapPath1)
        ) {
            revert Errors.MissingMultihopSwapPath();
        }

        require(
            s.liquidityOf[_params.investor] > 0,
            Errors.InvestorHasNoLiquidity()
        );

        Core.syncInvestor(s, _params.investor);
        updateLiquidity(s, _position);
        Rewards.updateRewardsOf(
            s,
            _position,
            _params.investor,
            address(_position)
        );

        uint128 _removeUniswapLiquidity = _calcRemoveLiquidityFromPercentage(
            s.uniswapLiquidityOf[_params.investor],
            _params.percentage
        );

        uint128 removeLiquidity = _calcRemoveLiquidityFromPercentage(
            s.liquidityOf[_params.investor],
            _params.percentage
        );

        (uint256 refund0, uint256 refund1) = _position
            .poolPositionView()
            .refundBalanceOf(_params.investor);

        (uint128 _liq0, uint128 _liq1) = UniswapV3Integration
            .getLiquidityFromAmounts(_position, refund0, refund1);

        uint128 refundUniswapLiquidity = _liq0 < _liq1 ? _liq0 : _liq1;

        uint128 removeUniswapLiquidity = _removeUniswapLiquidity >
            refundUniswapLiquidity
            ? refundUniswapLiquidity +
                (_removeUniswapLiquidity - refundUniswapLiquidity)
            : refundUniswapLiquidity +
                (refundUniswapLiquidity - _removeUniswapLiquidity);

        if (_params.investor == s.i_operator) {
            uint128 liquidity = s.liquidityOf[_params.investor] >
                s.operatorMintLiquidity[_params.investor]
                ? s.liquidityOf[_params.investor] -
                    s.operatorMintLiquidity[_params.investor]
                : 0;
            /// @dev check if operator is removing more than 50% of his mint liquidity. If so, we close the position
            if (
                removeLiquidity >
                ((s.operatorMintLiquidity[_params.investor] + liquidity) / 2)
            ) {
                // slither-disable-next-line unused-return
                (
                    ,
                    ,
                    ,
                    uint128 operatorLiquidity,
                    uint256 operatorDecAmount0,
                    uint256 operatorDecAmount1,
                    uint256 operatorCollectedCurrency0,
                    uint256 operatorCollectedCurrency1
                ) = Core.closePosition(
                        s,
                        _position,
                        address(_position),
                        _params.deadline,
                        _params.swapAllToStableCurrency
                    );

                IFeesVaultManager(s.i_feesVaultManager).withdraw(
                    operatorCollectedCurrency0,
                    operatorCollectedCurrency1
                );

                (uint256 _collectedFees0, uint256 _collectedFees1) = PayMaster
                    .splitCollectedFees(
                        _position,
                        s.i_operator,
                        operatorCollectedCurrency0,
                        operatorCollectedCurrency1
                    );

                PayMaster.transferTokens(
                    _position,
                    s.i_operator,
                    operatorDecAmount0 + _collectedFees0,
                    operatorDecAmount1 + _collectedFees1,
                    _params.swap
                );

                return (
                    operatorLiquidity,
                    operatorDecAmount0,
                    operatorDecAmount1
                );
            }
        }

        require(
            removeLiquidity <= s.liquidity &&
                removeLiquidity <= s.liquidityOf[_params.investor],
            Errors.RemovePercentageTooHigh(removeLiquidity)
        );

        (
            uint256 decAmount0,
            uint256 decAmount1,
            uint256 amount0Uniswap,
            uint256 amount1Uniswap
        ) = Core.decrease(
                s,
                _position,
                _params.investor,
                removeUniswapLiquidity,
                _params.amount0Min,
                _params.amount1Min,
                _params.deadline
            );

        updateLiquidity(s, _position);
        s.uniswapLiquidityOf[_params.investor] -= removeUniswapLiquidity;

        s.liquidity -= removeLiquidity;
        s.liquidityOf[_params.investor] -= removeLiquidity;

        uint256 earned0 = s.earned0Of[_params.investor];
        uint256 earned1 = s.earned1Of[_params.investor];
        s.earned0Of[_params.investor] = 0;
        s.earned1Of[_params.investor] = 0;

        // slither-disable-start unused-return
        // aderyn-ignore-next-line
        UniswapV3Integration.collect({
            s: s,
            _recipient: address(_position),
            _amount0Max: uint128(amount0Uniswap), // aderyn-ignore(unsafe-casting-detector)
            _amount1Max: uint128(amount1Uniswap) // aderyn-ignore(unsafe-casting-detector)
        });
        // slither-disable-end unused-return

        IFeesVaultManager(s.i_feesVaultManager).withdraw(earned0, earned1);

        (uint256 collectedFees0, uint256 collectedFees1) = PayMaster
            .splitCollectedFees(_position, _params.investor, earned0, earned1);

        // slither-disable-start unused-return
        (
            ,
            ,
            ,
            ,
            ,
            ,
            ISnapshotManagerStructs.Percentage[] memory percentages
        ) = ISnapshotManager(s.i_snapshotManager).virtualSyncInvestor(
                _params.investor
            );
        // slither-disable-end unused-return

        uint256 length = percentages.length;
        for (uint256 i = 0; i < length; i++) {
            // aderyn-ignore-next-line(unchecked-return)
            IRefundVaultManager(s.i_refundVaultManager).refund(
                percentages[i].positionSnapshotIndex,
                _params.investor,
                percentages[i].percentage
            );
            ISnapshotManager(s.i_snapshotManager).settlePercentage(
                percentages[i].positionSnapshotIndex,
                _params.investor
            );
        }

        PayMaster.transferTokens(
            _position,
            _params.investor,
            decAmount0 + collectedFees0,
            decAmount1 + collectedFees1,
            _params.swap
        );

        ISnapshotManager(s.i_snapshotManager).takeInvestorSnapshot(
            _params.investor,
            s.liquidityOf[_params.investor],
            s.earned0Of[_params.investor],
            s.earned1Of[_params.investor],
            s.rewardIndex0Of[_params.investor],
            s.rewardIndex1Of[_params.investor]
        );

        return (removeLiquidity, decAmount0, decAmount1);
    }

    /**
     * @notice Updates the liquidity of a pool position.
     * @param s The storage reference for the pool position.
     */
    function updateLiquidity(
        Storage storage s,
        IPoolPartyPosition _position
    ) internal {
        // slither-disable-next-line reentrancy-no-eth,unused-return
        (, , s.uniswapLiquidity, , ) = UniswapV3Integration.getPoolPositionInfo(
            _position
        );
    }

    /**
     * @notice Checks the multihop swap paths for increasing liquidity.
     * @param s The storage reference for the pool position.
     * @param _swap The swap parameters.
     * @param _amount0StableCurrency The amount of StableCurrency for currency0.
     * @param _amount1StableCurrency The amount of StableCurrency for currency1.
     */
    function _checkMultihopSwapPathForIncrease(
        Storage storage s,
        IPoolPartyPosition.SwapParams calldata _swap,
        uint256 _amount0StableCurrency,
        uint256 _amount1StableCurrency
    ) internal view {
        if (_swap.shouldSwapFees) {
            if (
                s.i_currency0 != s.i_stableCurrency &&
                _amount0StableCurrency > 0
            ) {
                require(
                    PayMaster._isValidMultihopSwapPath(_swap.multihopSwapPath0),
                    Errors.MissingMultihopSwapPathForCurrency0()
                );
            }
            if (
                s.i_currency1 != s.i_stableCurrency &&
                _amount1StableCurrency > 0
            ) {
                require(
                    PayMaster._isValidMultihopSwapPath(_swap.multihopSwapPath1),
                    Errors.MissingMultihopSwapPathForCurrency1()
                );
            }
        }
    }

    /**
     * @notice Refunds excess liquidity from an increase operation.
     * @param s The storage reference for the pool position.
     * @param _position The view of the pool position.
     * @param _swap The swap parameters.
     * @param _investor The address of the investor to receive the refund.
     * @param amount0Refund The amount of currency0 to refund.
     * @param amount1Refund The amount of currency1 to refund.
     */
    function _refundFromIncrease(
        Storage storage s,
        IPoolPartyPosition _position,
        IPoolPartyPosition.SwapParams calldata _swap,
        address _investor,
        uint256 amount0Refund,
        uint256 amount1Refund
    ) internal {
        if (
            amount0Refund > MIN_REFUND_AMOUNT &&
            PayMaster._isValidMultihopSwapPath(_swap.multihopSwapRefundPath0)
        ) {
            // slither-disable-start unused-return
            // aderyn-ignore-next-line
            PayMaster.swapToStableCurrency(
                _position,
                s.i_currency0,
                _swap.multihopSwapRefundPath0,
                amount0Refund,
                _investor,
                0
            );
            // slither-disable-end unused-return
        }
        if (
            amount1Refund > MIN_REFUND_AMOUNT &&
            PayMaster._isValidMultihopSwapPath(_swap.multihopSwapRefundPath1)
        ) {
            // slither-disable-start unused-return
            // aderyn-ignore-next-line
            PayMaster.swapToStableCurrency(
                _position,
                s.i_currency1,
                _swap.multihopSwapRefundPath1,
                amount1Refund,
                _investor,
                0
            );
            // slither-disable-end unused-return
        }
    }

    function _calcAddLiquidity(
        uint128 _liquidity,
        uint256 _amount0,
        uint256 _amount1
    ) public pure returns (uint128) {
        return
            _liquidity +
            UniswapV3Integration.getLiquidityFromFixedSqrtPrice(
                _amount0,
                _amount1
            );
    }

    function _calcRemoveLiquidityFromPercentage(
        uint128 _liquidity,
        uint256 _percentage
    ) private pure returns (uint128) {
        return
            uint128(
                (_percentage * _liquidity) /
                    (HUNDRED_PERCENT * REMOVE_PERCENTAGE_MULTIPLIER)
            );
    }
}
