// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Storage} from "../storage/PoolPartyPositionStorage.sol";
import {PayMaster} from "./PayMaster.sol";
import {Rewards} from "./Rewards.sol";
import {Liquidity} from "./Liquidity.sol";
import {Core} from "./Core.sol";
import {Errors} from "../interfaces/Errors.sol";
import {IFeesVaultManager} from "../interfaces/IFeesVaultManager.sol";
import "../interfaces/IPoolPartyPosition.sol";

/**
 * @title ClosePosition Library
 * @notice This library is used to handle the closing of positions within a Uniswap V3 pool.
 * It ensures that only the operator can close the position, updates liquidity and rewards,
 * and manages the transfer of collected fees and tokens.
 */
library ClosePosition {
    using PositionIdLib for PositionKey;

    /**
     * @notice Closes a position in the pool.
     * @param s The storage reference for the pool position.
     * @param _position The view of the pool position to be closed.
     * @param _params The parameters required to close the position.
     * @return liquidity The amount of liquidity removed from the position.
     * @return amount0 The amount of currency0 removed from the position.
     * @return amount1 The amount of currency1 removed from the position.
     */
    function closePosition(
        Storage storage s,
        IPoolPartyPosition _position,
        IPoolPartyPosition.ClosePositionParams calldata _params
    ) external returns (uint128 liquidity, uint256 amount0, uint256 amount1) {
        require(
            !_position.poolPositionView().isClosed(),
            Errors.PoolPositionAlreadyClosed()
        );
        require(
            _params.operator == s.i_operator,
            Errors.OnlyOperatorCanClosePosition()
        );

        Core.syncInvestor(s, s.i_operator);
        Liquidity.updateLiquidity(s, _position);
        Rewards.updateRewardsOf(s, _position, s.i_operator, address(_position));
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

        bytes memory zeroBytes = bytes("");
        IPoolPartyPositionStructs.SwapParams
            memory swap = IPoolPartyPositionStructs.SwapParams({
                shouldSwapFees: false,
                amount0OutMinimum: 0,
                amount1OutMinimum: 0,
                multihopSwapPath0: zeroBytes,
                multihopSwapPath1: zeroBytes,
                multihopSwapRefundPath0: zeroBytes,
                multihopSwapRefundPath1: zeroBytes
            });

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
            swap
        );
        return (operatorLiquidity, operatorDecAmount0, operatorDecAmount1);
    }
}
