// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {UniswapV3Integration} from "./UniswapV3Integration.sol";
import {Storage} from "../storage/PoolPartyPositionStorage.sol";
import "../interfaces/Constants.sol";
import {IFeesVaultManager} from "../interfaces/IFeesVaultManager.sol";
import "../interfaces/IPoolPartyPosition.sol";

/**
 * @title Rewards Library
 * @notice This library provides functions to manage and calculate rewards for pool positions.
 */
library Rewards {
    using PositionIdLib for PositionKey;
    using SafeERC20 for IERC20;

    /**
     * @notice Updates the rewards for a specific account.
     * @param s The storage reference for the pool position.
     * @param _account The account whose rewards are to be updated.
     * @param _recipient The address to receive the rewards.
     */
    function updateRewardsOf(
        Storage storage s,
        IPoolPartyPosition _poolPartyPosition,
        address _account,
        address _recipient
    ) internal {
        // slither-disable-start reentrancy-no-eth
        _updateRewardIndex(s, _poolPartyPosition, _recipient);
        s.earned0Of[_account] += _calculateRewards0(s, _account);
        s.rewardIndex0Of[_account] = s.rewardIndex0;
        s.earned1Of[_account] += _calculateRewards1(s, _account);
        s.rewardIndex1Of[_account] = s.rewardIndex1;
        // slither-disable-end reentrancy-no-eth
    }

    /**
     * @notice Calculates the rewards for currency0 for a specific account.
     * @param s The storage reference for the pool position.
     * @param _account The account whose rewards are to be calculated.
     * @return The amount of rewards for currency0.
     */
    function _calculateRewards0(
        Storage storage s,
        address _account
    ) internal view returns (uint256) {
        return
            (s.liquidityOf[_account] *
                (s.rewardIndex0 - s.rewardIndex0Of[_account])) /
            DENOMINATOR_MULTIPLIER;
    }

    /**
     * @notice Calculates the rewards for currency1 for a specific account.
     * @param s The storage reference for the pool position.
     * @param _account The account whose rewards are to be calculated.
     * @return The amount of rewards for currency1.
     */
    function _calculateRewards1(
        Storage storage s,
        address _account
    ) internal view returns (uint256) {
        return
            (s.liquidityOf[_account] *
                (s.rewardIndex1 - s.rewardIndex1Of[_account])) /
            DENOMINATOR_MULTIPLIER;
    }

    /**
     * @notice Updates the reward index for a specific recipient.
     * @param s The storage reference for the pool position.
     * @param _recipient The address to receive the rewards.
     */
    function _updateRewardIndex(
        Storage storage s,
        IPoolPartyPosition _poolPartyPosition,
        address _recipient
    ) internal {
        //slither-disable-next-line unused-return
        (
            ,
            ,
            ,
            uint256 _tokensOwed0,
            uint256 _tokensOwed1
        ) = UniswapV3Integration.getPoolPositionInfo(_poolPartyPosition);

        (uint256 tokensOwed0, uint256 tokensOwed1) = UniswapV3Integration
            .collect(
                s,
                _recipient,
                uint128(_tokensOwed0), // aderyn-ignore(unsafe-casting-detector)
                uint128(_tokensOwed1) // aderyn-ignore(unsafe-casting-detector)
            );

        (uint256 rewardIndex0, uint256 rewardIndex1) = rewardsIndexes(
            s.liquidity,
            tokensOwed0,
            tokensOwed1
        );

        s.rewardIndex0 += rewardIndex0;
        s.rewardIndex1 += rewardIndex1;

        IERC20(s.i_currency0).forceApprove(s.i_feesVaultManager, tokensOwed0);
        IERC20(s.i_currency1).forceApprove(s.i_feesVaultManager, tokensOwed1);
        IFeesVaultManager(s.i_feesVaultManager).deposit(
            tokensOwed0,
            tokensOwed1
        );

        // slither-disable-next-line reentrancy-events
        emit IPoolPartyPositionEvents.PositionRewardsCollected(
            s.positionKey.toId(),
            tokensOwed0,
            tokensOwed1
        );
    }

    /**
     * @notice Calculates the reward indexes based on liquidity and tokens owed.
     * @param _liquidity The amount of liquidity.
     * @param _tokensOwed0 The amount of currency0 owed.
     * @param _tokensOwed1 The amount of currency1 owed.
     * @return rewardIndex0 The reward index for currency0.
     * @return rewardIndex1 The reward index for currency1.
     */
    function rewardsIndexes(
        uint128 _liquidity,
        uint256 _tokensOwed0,
        uint256 _tokensOwed1
    ) public pure returns (uint256 rewardIndex0, uint256 rewardIndex1) {
        if (_tokensOwed0 > 0 && _liquidity > 0) {
            rewardIndex0 = (_tokensOwed0 * DENOMINATOR_MULTIPLIER) / _liquidity;
        }
        if (_tokensOwed1 > 0 && _liquidity > 0) {
            rewardIndex1 = (_tokensOwed1 * DENOMINATOR_MULTIPLIER) / _liquidity;
        }
    }
}
