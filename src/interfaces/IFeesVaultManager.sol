// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

interface IFeesVaultManagerEvents {
    /**
     * @notice Emitted when a deposit is made
     * @param currency0 The currency0 address
     * @param currency1 The currency1 address
     * @param fees0 The fees0 amount
     * @param fees1 The fees1 amount
     */
    // aderyn-ignore-next-line(unindexed-events)
    event Deposited(
        address indexed currency0,
        address indexed currency1,
        uint256 fees0,
        uint256 fees1
    );

    /**
     * @notice Emitted when a fees is payed
     * @param to The address to pay fees to
     * @param currency0 The currency0 address
     * @param currency1 The currency1 address
     * @param fees0 The fees0 amount
     * @param fees1 The fees1 amount
     */
    // aderyn-ignore-next-line(unindexed-events)
    event WithdrawnFees(
        address indexed to,
        address currency0,
        address currency1,
        uint256 fees0,
        uint256 fees1
    );

    /**
     * @notice Emitted when a deposit in stable is made
     * @param token The token address
     * @param fees The fees amount
     */
    // aderyn-ignore-next-line(unindexed-events)
    event DepositedInStable(address indexed token, uint256 fees);

    /**
     * @notice Emitted when a fees is payed in stable
     * @param to The address to pay fees to
     * @param token The stable address
     * @param fees The fees amount
     */
    // aderyn-ignore-next-line(unindexed-events)
    event WithdrawnFeeInStable(address indexed to, address token, uint256 fees);
}

interface IFeesVaultManagerStructs {}

interface IFeesVaultManager is
    IFeesVaultManagerStructs,
    IFeesVaultManagerEvents
{
    /**
     * @notice Deposits fees in the specified currencies.
     * @param _fees0 The amount of the first currency to deposit.
     * @param _fees1 The amount of the second currency to deposit.
     */
    function deposit(uint256 _fees0, uint256 _fees1) external;

    /**
     * @notice Withdraws fees in the specified currencies.
     * @param _fees0 The amount of the first currency to withdraw.
     * @param _fees1 The amount of the second currency to withdraw.
     */
    function withdraw(uint256 _fees0, uint256 _fees1) external;

    /**
     * @notice Deposits fees in the stable currency.
     * @param _fees The amount of the stable currency to deposit.
     */
    function depositInStableCurrency(uint256 _fees) external;

    /**
     * @notice Withdraws fees in the stable currency.
     * @param _amount The amount of the stable currency to withdraw.
     */
    function withdrawInStableCurrency(uint256 _amount) external;

    /**
     * @notice Gets the current balance of fees in all currencies.
     * @return (uint256, uint256, uint256) The amounts of the first currency, second currency, and stable currency.
     */
    function getFees() external view returns (uint256, uint256, uint256);
}
