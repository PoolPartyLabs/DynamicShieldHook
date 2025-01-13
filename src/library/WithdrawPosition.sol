// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {FullMath} from "./uniswap/FullMath.sol";
import {PayMaster} from "./PayMaster.sol";
import {UniswapV3Integration} from "./UniswapV3Integration.sol";
import {Rewards} from "./Rewards.sol";
import {Liquidity} from "./Liquidity.sol";
import {Core} from "./Core.sol";
import "../interfaces/Constants.sol";
import {Errors} from "../interfaces/Errors.sol";
import {Storage} from "../storage/PoolPartyPositionStorage.sol";
import {ISnapshotManager, ISnapshotManagerStructs} from "../interfaces/ISnapshotManager.sol";
import {IFeesVaultManager} from "../interfaces/IFeesVaultManager.sol";
import {IRefundVaultManager} from "../interfaces/IRefundVaultManager.sol";
import "../interfaces/IPoolPartyPosition.sol";

/**
 * @title WithdrawPosition Library
 * @notice This library handles the withdrawal of positions from a Uniswap V3 pool.
 * It ensures that the required conditions are met and manages the transfer of tokens and fees.
 */
library WithdrawPosition {
    using PositionIdLib for PositionKey;
    using SafeERC20 for IERC20;

    /**
     * @notice Withdraws a position from the pool.
     * @param s The storage reference for the pool position.
     * @param _position The view of the pool position.
     * @param _params The parameters required to withdraw the position.
     * @return amount0 The amount of currency0 withdrawn.
     * @return amount1 The amount of currency1 withdrawn.
     * @return netEarned0 The net amount of currency0 earned.
     * @return netEarned1 The net amount of currency1 earned.
     */
    function withdraw(
        Storage storage s,
        IPoolPartyPosition _position,
        IPoolPartyPosition.WithdrawParams calldata _params
    ) external returns (uint256, uint256, uint256, uint256) {
        //slither-disable-next-line timestamp
        require(_params.deadline >= block.timestamp, Errors.ExpiredDeadline());

        require(_params.investor != address(0), Errors.AddressIsZero());

        require(
            _params.investor != s.i_operator,
            Errors.InvestorMustNotBeOperator()
        );

        require(
            s.liquidityOf[_params.investor] > 0,
            Errors.InvestorHasNoLiquidity()
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

        Core.syncInvestor(s, _params.investor);
        Liquidity.updateLiquidity(s, _position);
        Rewards.updateRewardsOf(
            s,
            _position,
            _params.investor,
            address(_position)
        );
        uint256 _remainingLiquidityAfterClose = s.remainingLiquidityAfterClose;
        uint128 prevLiquidity = s.liquidityOf[_params.investor];

        uint256 netEarned0 = 0;
        uint256 netEarned1 = 0;
        (
            ,
            uint256 amount0,
            uint256 amount1,
            uint128 earned0,
            uint128 earned1
        ) = Core.withdraw(
                s,
                _position,
                address(_position),
                _params.investor,
                _params.deadline
            );

        if (
            _position.poolPositionView().isClosed() &&
            s.isAllLiquiditySwappedToStableCurrency &&
            _remainingLiquidityAfterClose > 0
        ) {
            uint256 totalLiquidityInStableCurrency = s
                .totalLiquidityInStableCurrency;

            uint256 percentageLiquidity = FullMath.mulDiv(
                prevLiquidity,
                DENOMINATOR_MULTIPLIER,
                _remainingLiquidityAfterClose
            );

            uint256 liquidityInStableCurrency = FullMath.mulDiv(
                totalLiquidityInStableCurrency,
                percentageLiquidity,
                DENOMINATOR_MULTIPLIER
            );

            if (totalLiquidityInStableCurrency >= liquidityInStableCurrency) {
                s.totalLiquidityInStableCurrency -= liquidityInStableCurrency;
            }

            uint256 earnedInStableCurrency = _calcEarnedInStableCurrency(
                s,
                earned0,
                earned1
            );

            IFeesVaultManager(s.i_feesVaultManager).withdrawInStableCurrency(
                earnedInStableCurrency
            );

            // aderyn-ignore-next-line(unchecked-return)
            _refundInStableCurrency(s, _params.investor);

            netEarned0 = PayMaster.splitCollectedFeesInStableCurrency(
                _position,
                _params.investor,
                earnedInStableCurrency
            );

            PayMaster.transferStableCurrency(
                _position,
                _params.investor,
                liquidityInStableCurrency + netEarned0
            );

            // slither-disable-next-line reentrancy-events
            emit IPoolPartyPositionEvents.WithdrawnInStableCurrency(
                _params.investor,
                _position.poolPositionView().key().toId(),
                liquidityInStableCurrency + netEarned0
            );
        } else {
            IFeesVaultManager(s.i_feesVaultManager).withdraw(earned0, earned1);

            (netEarned0, netEarned1) = PayMaster.splitCollectedFees(
                _position,
                _params.investor,
                earned0,
                earned1
            );

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
                if (percentages[i].percentage == 0) {
                    continue;
                }
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
                amount0 + netEarned0,
                amount1 + netEarned1,
                _params.swap
            );

            // slither-disable-next-line reentrancy-events
            emit IPoolPartyPositionEvents.Withdrawn(
                _params.investor,
                _position.poolPositionView().key().toId(),
                amount0 + netEarned0,
                amount1 + netEarned1
            );
        }

        if (s.remainingLiquidityAfterClose == 0) {
            PayMaster.withdrawRemainingTokens(s, _position);
        }

        return (amount0, amount1, netEarned0, netEarned1);
    }

    /**
     * @notice Calculates the earned amount in StableCurrency.
     * @param s The storage reference for the pool position.
     * @param earned0 The amount of currency0 earned.
     * @param earned1 The amount of currency1 earned.
     * @return earnedInStableCurrency The amount of earned StableCurrency.
     */
    function _calcEarnedInStableCurrency(
        Storage storage s,
        uint256 earned0,
        uint256 earned1
    ) internal returns (uint256 earnedInStableCurrency) {
        uint256 totalCollectedFeesInStableCurrency = s
            .totalCollectedFeesInStableCurrency;

        if (
            s.liquidityForCollectedFees == 0 ||
            totalCollectedFeesInStableCurrency == 0
        ) {
            return 0;
        }

        uint128 liquidityCollected = UniswapV3Integration
            .getLiquidityFromFixedSqrtPrice(earned0, earned1);

        uint256 percentageEarnedLiquidity = FullMath.mulDiv(
            liquidityCollected,
            DENOMINATOR_MULTIPLIER,
            s.liquidityForCollectedFees
        );

        earnedInStableCurrency = FullMath.mulDiv(
            totalCollectedFeesInStableCurrency,
            percentageEarnedLiquidity,
            DENOMINATOR_MULTIPLIER
        );

        if (totalCollectedFeesInStableCurrency >= earnedInStableCurrency) {
            s.totalCollectedFeesInStableCurrency -= earnedInStableCurrency;
        }

        if (liquidityCollected <= s.liquidityForCollectedFees) {
            s.liquidityForCollectedFees -= liquidityCollected;
        }
    }

    function _refundInStableCurrency(
        Storage storage s,
        address _investor
    ) internal returns (uint256 refundInStableCurrency) {
        uint256 totalRefundInStableCurrency = s.totalRefundInStableCurrency;
        if (totalRefundInStableCurrency == 0) {
            return 0;
        }
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
                _investor
            );
        // slither-disable-end unused-return
        uint256 length = percentages.length;
        for (uint256 i = 0; i < length; i++) {
            if (percentages[i].percentage == 0) {
                continue;
            }
            refundInStableCurrency += IRefundVaultManager(
                s.i_refundVaultManager
            ).refundInStable(
                    percentages[i].positionSnapshotIndex,
                    _investor,
                    percentages[i].percentage
                );
            ISnapshotManager(s.i_snapshotManager).settlePercentage(
                percentages[i].positionSnapshotIndex,
                _investor
            );
        }
        if (totalRefundInStableCurrency >= refundInStableCurrency) {
            s.totalRefundInStableCurrency -= refundInStableCurrency;
        }
    }
}
