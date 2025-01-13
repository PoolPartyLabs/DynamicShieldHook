// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

/**
 * @title FeesVaultManagerFactory Interface
 */
interface IFeesVaultManagerFactory {
    function create(
        address _owner,
        address _currency0,
        address _currency1,
        address _stableCurrency
    ) external returns (address feesVaultManager);
}
