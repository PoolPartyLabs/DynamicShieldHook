// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {UniswapV3Integration} from "./UniswapV3Integration.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {PayMaster} from "./PayMaster.sol";
import {Storage} from "../storage/PoolPartyPositionStorage.sol";
import {ISnapshotManagerStructs} from "../interfaces/ISnapshotManager.sol";
import {ISnapshotManager} from "../interfaces/ISnapshotManager.sol";
import {IFeesVaultManager} from "../interfaces/IFeesVaultManager.sol";
import {IRefundVaultManager} from "../interfaces/IRefundVaultManager.sol";
import "../interfaces/Constants.sol";
import "../interfaces/IPoolPartyPosition.sol";

/**
 * @title Core Library
 * @notice This library provides core functionalities for managing Uniswap V3 pool positions,
 * including decreasing liquidity, collecting earned fees, closing positions, and withdrawing funds.
 */
// aderyn-ignore-next-line(reused-contract-name)
library Core {
    using PositionIdLib for PositionKey;
    using SafeERC20 for IERC20;

    /**
     * @notice Decreases liquidity from a pool position.
     * @param s The storage reference for the pool position.
     * @param _account The account from which liquidity is to be decreased.
     * @param _liquidity The amount of liquidity to be decreased.
     * @param _amount0Min The minimum amount of currency0 to be received.
     * @param _amount1Min The minimum amount of currency1 to be received.
     * @param _deadline The deadline by which the decrease must be completed.
     * @return amount0 The amount of currency0 received.
     * @return amount1 The amount of currency1 received.
     * @return amount0Uniswap The amount of currency0 received from Uniswap.
     * @return amount1Uniswap The amount of currency1 received from Uniswap.
     */
    function decrease(
        Storage storage s,
        IPoolPartyPosition _position,
        address _account,
        uint128 _liquidity,
        uint256 _amount0Min,
        uint256 _amount1Min,
        uint256 _deadline
    )
        external
        returns (
            uint256 amount0,
            uint256 amount1,
            uint256 amount0Uniswap,
            uint256 amount1Uniswap
        )
    {
        if (_liquidity == 0) {
            return (0, 0, 0, 0);
        }

        // slither-disable-start reentrancy-benign,reentrancy-events,unused-return
        // aderyn-ignore-next-line
        (amount0Uniswap, amount1Uniswap) = UniswapV3Integration.decrease({
            s: s,
            _liquidity: _liquidity,
            _amount0Min: _amount0Min,
            _amount1Min: _amount1Min,
            _deadline: _deadline
        });
        // slither-disable-end reentrancy-benign,reentrancy-events,unused-return

        (amount0, amount1) = UniswapV3Integration.getAmountsFromLiquidity(
            _position,
            _liquidity
        );

        emit IPoolPartyPositionEvents.LiquidityRemoved(
            _account,
            s.positionKey.toId(),
            _liquidity,
            amount0,
            amount1
        );
    }

    /**
     * @notice Closes a pool position.
     * @param s The storage reference for the pool position.
     * @param _position The view of the pool position to be closed.
     * @param _recipient The address to receive the collected tokens.
     * @param _deadline The deadline by which the position must be closed.
     * @param _swap The parameters for swapping all tokens to StableCurrency.
     * @return _liquidity The amount of liquidity removed.
     * @return _tokensDecreased0 The amount of currency0 removed.
     * @return _tokensDecreased1 The amount of currency1 removed.
     * @return _operatorLiquidity The amount of liquidity removed by the operator.
     * @return _operatorAmount0 The amount of currency0 removed by the operator.
     * @return _operatorAmount1 The amount of currency1 removed by the operator.
     * @return _operatorCollectedCurrency0 The amount of currency0 collected by the operator.
     * @return _operatorCollectedCurrency1 The amount of currency1 collected by the operator.
     */
    function closePosition(
        Storage storage s,
        IPoolPartyPosition _position,
        address _recipient,
        uint256 _deadline,
        IPoolPartyPosition.SwapAllToStableCurrencyParams calldata _swap
    )
        external
        returns (
            uint128 _liquidity,
            uint256 _tokensDecreased0,
            uint256 _tokensDecreased1,
            uint128 _operatorLiquidity,
            uint256 _operatorAmount0,
            uint256 _operatorAmount1,
            uint256 _operatorCollectedCurrency0,
            uint256 _operatorCollectedCurrency1
        )
    {
        PositionId posisionId = s.positionKey.toId();
        uint128 prevLiquidity = s.liquidity;
        uint128 prevUniswapLiquidity = s.uniswapLiquidity;

        // slither-disable-next-line unused-return
        (uint160 sqrtPriceX96Pool, , , , , , ) = IUniswapV3Pool(
            s.positionKey.pool
        ).slot0();

        s.sqrtPriceX96BeforeClose = sqrtPriceX96Pool;

        // slither-disable-next-line unused-return
        (
            ,
            ,
            ,
            uint256 positionTokensCollected0,
            uint256 positionTokensCollected1
        ) = UniswapV3Integration.getPoolPositionInfo(_position);

        //slither-disable-start reentrancy-events,reentrancy-no-eth
        // aderyn-ignore-next-line
        (
            uint256 tokensDecreased0,
            uint256 tokensDecreased1
        ) = UniswapV3Integration.decrease({
                s: s,
                _liquidity: prevUniswapLiquidity,
                _amount0Min: 0,
                _amount1Min: 0,
                _deadline: _deadline
            });
        //slither-disable-end reentrancy-events,reentrancy-no-eth

        uint128 operatorCollectedCurrency0 = uint128(s.earned0Of[s.i_operator]);
        uint128 operatorCollectedCurrency1 = uint128(s.earned1Of[s.i_operator]);

        //slither-disable-start reentrancy-events,reentrancy-no-eth,unused-return
        // aderyn-ignore-next-line
        UniswapV3Integration.collect({
            s: s,
            _recipient: _recipient,
            _amount0Max: type(uint128).max,
            _amount1Max: type(uint128).max
        });
        //slither-disable-end reentrancy-events,reentrancy-no-eth,unused-return

        uint128 removedOpLiquidty = s.liquidityOf[s.i_operator];
        (_operatorAmount0, _operatorAmount1) = UniswapV3Integration
            .getAmountsFromLiquidity(
                _position,
                s.uniswapLiquidityOf[s.i_operator]
            );

        if (_swap.swapAllToStableCurrency) {
            _swapAllToStableCurrency(
                s,
                _position,
                _swap,
                prevUniswapLiquidity,
                _operatorAmount0,
                _operatorAmount1,
                operatorCollectedCurrency0,
                operatorCollectedCurrency1
            );
        }

        s.liquidityBeforeClose = prevLiquidity;
        s.uniswapLiquidityBeforeClose = prevUniswapLiquidity;
        s.remainingLiquidityAfterClose = prevLiquidity - removedOpLiquidty;

        s.liquidityOf[s.i_operator] = 0;
        s.uniswapLiquidityOf[s.i_operator] = 0;
        s.earned0Of[s.i_operator] = 0;
        s.earned1Of[s.i_operator] = 0;

        _closePoolPosition(s, posisionId);
        s.liquidity = 0;
        s.uniswapLiquidity = 0;

        emit IPoolPartyPositionEvents.LiquidityRemoved(
            s.i_operator,
            posisionId,
            removedOpLiquidty,
            _operatorAmount0,
            _operatorAmount1
        );

        emit IPoolPartyPositionEvents.AllRewardsCollected(
            posisionId,
            positionTokensCollected0,
            positionTokensCollected1
        );

        emit IPoolPartyPositionEvents.PositionClosed(
            posisionId,
            address(_recipient),
            prevLiquidity,
            tokensDecreased0,
            tokensDecreased1
        );

        return (
            prevLiquidity,
            tokensDecreased0,
            tokensDecreased1,
            removedOpLiquidty,
            _operatorAmount0,
            _operatorAmount1,
            operatorCollectedCurrency0,
            operatorCollectedCurrency1
        );
    }

    /**
     * @notice Withdraws funds from a pool position.
     * @param s The storage reference for the pool position.
     * @param _position The view of the pool position from which funds are to be withdrawn.
     * @param _recipient The address to receive the withdrawn funds.
     * @param _investor The investor whose funds are to be withdrawn.
     * @param _deadline The deadline by which the withdrawal must be completed.
     * @return liquidity The amount of liquidity withdrawn.
     * @return amount0 The amount of currency0 withdrawn.
     * @return amount1 The amount of currency1 withdrawn.
     * @return earned0 The amount of currency0 earned.
     * @return earned1 The amount of currency1 earned.
     */
    // aderyn-ignore-next-line(state-variable-changes-without-events)
    function withdraw(
        Storage storage s,
        IPoolPartyPosition _position,
        address _recipient,
        address _investor,
        uint256 _deadline
    )
        external
        returns (
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1,
            uint128 earned0,
            uint128 earned1
        )
    {
        earned0 = uint128(s.earned0Of[_investor]);
        earned1 = uint128(s.earned1Of[_investor]);

        //slither-disable-start unused-return,reentrancy-no-eth
        uint128 _liquidity = s.uniswapLiquidityOf[_investor];

        (amount0, amount1) = UniswapV3Integration.getAmountsFromLiquidity(
            _position,
            _liquidity
        );

        if (!_position.poolPositionView().isClosed() && _liquidity > 0) {
            // aderyn-ignore-next-line
            (uint256 _amount0, uint256 _amount1) = UniswapV3Integration
                .decrease({
                    s: s,
                    _liquidity: _liquidity,
                    _amount0Min: 0,
                    _amount1Min: 0,
                    _deadline: _deadline
                });

            // aderyn-ignore-next-line
            UniswapV3Integration.collect({
                s: s,
                _recipient: _recipient,
                _amount0Max: earned0 + uint128(_amount0),
                _amount1Max: earned1 + uint128(_amount1)
            });
        } else {
            // aderyn-ignore-next-line
            UniswapV3Integration.collect({
                s: s,
                _recipient: _recipient,
                _amount0Max: earned0 + uint128(amount0),
                _amount1Max: earned1 + uint128(amount1)
            });
        }
        //slither-disable-end unused-return,reentrancy-no-eth

        if (s.remainingLiquidityAfterClose > 0) {
            s.remainingLiquidityAfterClose -= s.liquidityOf[_investor];
        }

        s.liquidityOf[_investor] = 0;
        s.uniswapLiquidityOf[_investor] = 0;
        s.earned0Of[_investor] = 0;
        s.earned1Of[_investor] = 0;

        return (_liquidity, amount0, amount1, earned0, earned1);
    }

    // aderyn-ignore-next-line(state-variable-changes-without-events)
    function syncInvestor(Storage storage s, address _account) external {
        uint256 positionSnapshotIndex = ISnapshotManager(s.i_snapshotManager)
            .getPositionSnapshotIndex();
        if (positionSnapshotIndex > 0) {
            ISnapshotManager(s.i_snapshotManager).syncInvestor(_account);
            ISnapshotManagerStructs.InvestorState
                memory investorState = ISnapshotManager(s.i_snapshotManager)
                    .getInvestorSnapshot(_account);
            s.liquidityOf[_account] = investorState.liquidity;
            s.rewardIndex0Of[_account] = investorState.lastIndex0;
            s.rewardIndex1Of[_account] = investorState.lastIndex1;
            s.earned0Of[_account] = investorState.fees0;
            s.earned1Of[_account] = investorState.fees1;
            uint256 uniswapLiquidity = s.uniswapLiquidity;
            uint256 liquidity = s.liquidity;

            if (
                !s.isOpen[s.positionKey.toId()][s.tokenId] ||
                liquidity == 0 ||
                uniswapLiquidity == 0
            ) {
                uniswapLiquidity = s.uniswapLiquidityBeforeClose;
                liquidity = s.liquidityBeforeClose;
            }

            uint256 percentage = liquidity > 0
                ? ((s.liquidityOf[_account] * DENOMINATOR_MULTIPLIER) /
                    liquidity)
                : 0;
            s.uniswapLiquidityOf[_account] = uint128(
                (uniswapLiquidity * percentage) / DENOMINATOR_MULTIPLIER
            );
        }
    }

    function _swapAllToStableCurrency(
        Storage storage s,
        IPoolPartyPosition _position,
        IPoolPartyPosition.SwapAllToStableCurrencyParams calldata _swap,
        uint128 _prevLiquidity,
        uint256 _operatorAmount0,
        uint256 _operatorAmount1,
        uint256 operatorCollectedCurrency0,
        uint256 operatorCollectedCurrency1
    ) private {
        (uint256 _amount0, uint256 _amount1) = UniswapV3Integration
            .getAmountsFromLiquidity(_position, _prevLiquidity);

        uint256 diffAmount0 = _amount0 - _operatorAmount0;

        uint256 diffAmount1 = _amount1 - _operatorAmount1;

        // slither-disable-next-line unused-return
        (uint256 fees0, uint256 fees1, ) = IFeesVaultManager(
            s.i_feesVaultManager
        ).getFees();

        uint256 feeAmount0 = fees0 - operatorCollectedCurrency0;
        uint256 feeAmount1 = fees1 - operatorCollectedCurrency1;
        IFeesVaultManager(s.i_feesVaultManager).withdraw(
            feeAmount0,
            feeAmount1
        );
        {
            uint256 currency0InStableCurrency = PayMaster.swapToStableCurrency(
                _position,
                s.i_currency0,
                _swap.multihopSwapPath0,
                diffAmount0,
                address(_position),
                0
            );

            uint256 currency1InStableCurrency = PayMaster.swapToStableCurrency(
                _position,
                s.i_currency1,
                _swap.multihopSwapPath1,
                diffAmount1,
                address(_position),
                0
            );
            s.totalLiquidityInStableCurrency =
                currency0InStableCurrency +
                currency1InStableCurrency;

            uint256 fee0InStableCurrency = PayMaster.swapToStableCurrency(
                _position,
                s.i_currency0,
                _swap.multihopSwapPath0,
                feeAmount0,
                address(_position),
                0
            );

            uint256 fee1InStableCurrency = PayMaster.swapToStableCurrency(
                _position,
                s.i_currency1,
                _swap.multihopSwapPath1,
                feeAmount1,
                address(_position),
                0
            );

            (uint256 refund0, uint256 refund1) = IRefundVaultManager(
                s.i_refundVaultManager
            ).withdrawTokens();

            uint256 refund0InStableCurrency = PayMaster.swapToStableCurrency(
                _position,
                s.i_currency0,
                _swap.multihopSwapPath0,
                refund0,
                address(_position),
                0
            );

            uint256 refund1InStableCurrency = PayMaster.swapToStableCurrency(
                _position,
                s.i_currency1,
                _swap.multihopSwapPath1,
                refund1,
                address(_position),
                0
            );

            s.totalRefundInStableCurrency =
                refund0InStableCurrency +
                refund1InStableCurrency;

            s.totalCollectedFeesInStableCurrency =
                fee0InStableCurrency +
                fee1InStableCurrency;

            s.liquidityForCollectedFees = UniswapV3Integration
                .getLiquidityFromFixedSqrtPrice(feeAmount0, feeAmount1);

            IERC20(s.i_stableCurrency).forceApprove(
                s.i_refundVaultManager,
                s.totalRefundInStableCurrency
            );

            IRefundVaultManager(s.i_refundVaultManager)
                .realocateDepositInStable(s.totalRefundInStableCurrency);

            s.isAllLiquiditySwappedToStableCurrency = true;
            IERC20(s.i_stableCurrency).forceApprove(
                s.i_feesVaultManager,
                s.totalCollectedFeesInStableCurrency
            );
            IFeesVaultManager(s.i_feesVaultManager).depositInStableCurrency(
                s.totalCollectedFeesInStableCurrency
            );
        }
    }

    /**
     * @notice Closes a pool position internally.
     * @param s The storage reference for the pool position.
     * @param _id The ID of the position to be closed.
     */
    function _closePoolPosition(Storage storage s, PositionId _id) private {
        s.isOpen[_id][s.tokenId] = false;
        delete s.isOpen[_id][s.tokenId];
    }
}
