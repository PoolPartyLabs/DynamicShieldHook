// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {PayMaster} from "./PayMaster.sol";
import {Liquidity} from "./Liquidity.sol";
import {Rewards} from "./Rewards.sol";
import {Core} from "./Core.sol";
import {Errors} from "../interfaces/Errors.sol";
import {Storage} from "../storage/PoolPartyPositionStorage.sol";
import {IFeesVaultManager} from "../interfaces/IFeesVaultManager.sol";
import "../interfaces/IPoolPartyPosition.sol";

/**
 * @title CollectFees Library
 * @notice This library is used to handle the collection of fees from a Uniswap V3 pool position.
 * It ensures that fees are collected within a specified deadline and manages the distribution
 * of earned fees to the investor.
 */
library CollectFees {
    using PositionIdLib for PositionKey;

    /**
     * @notice Collects fees from a pool position.
     * @param s The storage reference for the pool position.
     * @param _position The view of the pool position from which fees are to be collected.
     * @param _params The parameters required to collect the fees.
     * @return earned0 The amount of currency0 earned from the position.
     * @return earned1 The amount of currency1 earned from the position.
     */
    function collect(
        Storage storage s,
        IPoolPartyPosition _position,
        IPoolPartyPositionStructs.CollectParams calldata _params
    ) external returns (uint256 earned0, uint256 earned1) {
        address investor = _params.investor;
        //slither-disable-next-line timestamp
        require(_params.deadline >= block.timestamp, Errors.ExpiredDeadline());

        require(investor != address(0), Errors.AddressIsZero());

        if (
            _params.swap.shouldSwapFees &&
            !PayMaster._isValidMultihopSwapPath(
                _params.swap.multihopSwapPath0
            ) &&
            !PayMaster._isValidMultihopSwapPath(_params.swap.multihopSwapPath1)
        ) {
            revert Errors.MissingMultihopSwapPath();
        }

        Core.syncInvestor(s, investor);
        Liquidity.updateLiquidity(s, _position);
        Rewards.updateRewardsOf(s, _position, investor, address(_position));

        earned0 = s.earned0Of[investor];
        earned1 = s.earned1Of[investor];

        require(earned0 > 0 || earned1 > 0, Errors.NoRewardsToCollect());

        s.earned0Of[investor] = 0;
        s.earned1Of[investor] = 0;

        IFeesVaultManager(s.i_feesVaultManager).withdraw(earned0, earned1);

        (uint256 collectedFees0, uint256 collectedFees1) = PayMaster
            .splitCollectedFees(_position, investor, earned0, earned1);

        PayMaster.transferTokens(
            _position,
            investor,
            collectedFees0,
            collectedFees1,
            _params.swap
        );
    }
}
