// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

interface IRefundVaultManagerEvents {
    /**
     * @notice Emitted when a deposit is made
     * @param snapshotIndex The snapshot index
     * @param currency0 The currency0 address
     * @param currency1 The currency1 address
     * @param amount0 The currency0 amount
     * @param amount1 The currency1 amount
     */
    // aderyn-ignore-next-line(unindexed-events)
    event Deposited(
        uint256 indexed snapshotIndex,
        address currency0,
        address currency1,
        uint256 amount0,
        uint256 amount1
    );

    /**
     * @notice Emitted when a refund is made
     * @param snapshotIndex The snapshot index
     * @param currency0 The currency0 address
     * @param currency1 The currency1 address
     * @param to The address to refund to
     * @param percentage The percentage
     * @param amount0 The currency0 amount
     * @param amount1 The currency1 amount
     */
    // aderyn-ignore-next-line(unindexed-events)
    event Refunded(
        uint256 indexed snapshotIndex,
        address currency0,
        address currency1,
        address indexed to,
        uint256 percentage,
        uint256 amount0,
        uint256 amount1
    );

    /**
     * @notice Emitted when a refund in stable is made
     * @param snapshotIndex The snapshot index
     * @param stable The stable address
     * @param to The address to refund to
     * @param percentage The percentage
     * @param amount The stable amount
     */
    // aderyn-ignore-next-line(unindexed-events)
    event RefundedInStable(
        uint256 indexed snapshotIndex,
        address stable,
        address indexed to,
        uint256 percentage,
        uint256 amount
    );

    /**
     * @notice Emitted when a realocate deposit in stable is made
     * @param amount The stable amount
     */
    // aderyn-ignore-next-line(unindexed-events)
    event RealocatedDepositInStable(uint256 amount);
}

interface IRefundVaultManagerStructs {
    struct Refund {
        uint256 snapshotIndex;
        uint256 initAmount0;
        uint256 initAmount1;
        uint256 amount0;
        uint256 amount1;
        uint256 initStableAmount;
        uint256 stableAmount;
        uint128 liquidity;
    }
}

interface IRefundVaultManager is
    IRefundVaultManagerStructs,
    IRefundVaultManagerEvents
{
    /**
     * @notice Deposits amounts in the specified currencies for a given snapshot index.
     * @param _snapshotIndex The index of the snapshot.
     * @param _amount0 The amount of the first currency to deposit.
     * @param _amount1 The amount of the second currency to deposit.
     */
    function deposit(
        uint256 _snapshotIndex,
        uint256 _amount0,
        uint256 _amount1
    ) external;

    /**
     * @notice Reallocates the deposit in stable currency.
     * @param _amount The amount to reallocate.
     */
    function realocateDepositInStable(uint256 _amount) external;

    /**
     * @notice Refunds a percentage of the amounts for a given snapshot index.
     * @param _snapshotIndex The index of the snapshot.
     * @param _to The address to send the refund to.
     * @param _percentage The percentage of the amounts to refund.
     * @return _amount0 The refunded amount of the first currency.
     * @return _amount1 The refunded amount of the second currency.
     */
    function refund(
        uint256 _snapshotIndex,
        address _to,
        uint256 _percentage
    ) external returns (uint256 _amount0, uint256 _amount1);

    /**
     * @notice Refunds a percentage of the stable currency for a given snapshot index.
     * @param _snapshotIndex The index of the snapshot.
     * @param _to The address to send the refund to.
     * @param _percentage The percentage of the stable currency to refund.
     * @return amount The refunded amount of the stable currency.
     */
    function refundInStable(
        uint256 _snapshotIndex,
        address _to,
        uint256 _percentage
    ) external returns (uint256 amount);

    /**
     * @notice Withdraws all tokens from the contract.
     * @return amount0 The amount of the first currency withdrawn.
     * @return amount1 The amount of the second currency withdrawn.
     */
    function withdrawTokens()
        external
        returns (uint256 amount0, uint256 amount1);

    /**
     * @notice Calculates the refund amounts for a given snapshot index and percentage.
     * @param _snapshotIndex The index of the snapshot.
     * @param _percentage The percentage to calculate the refund for.
     * @return amount0 The calculated refund amount of the first currency.
     * @return amount1 The calculated refund amount of the second currency.
     */
    function calcRefund(
        uint256 _snapshotIndex,
        uint256 _percentage
    ) external view returns (uint256 amount0, uint256 amount1);

    /**
     * @notice Gets the refund balance for a given snapshot index.
     * @param _snapshotIndex The index of the snapshot.
     * @return amount0 The refund balance of the first currency.
     * @return amount1 The refund balance of the second currency.
     */
    function refundBalanceBySnapshotIndex(
        uint256 _snapshotIndex
    ) external view returns (uint256 amount0, uint256 amount1);

    /**
     * @notice Gets the total refund balance in all currencies.
     * @return amount0 The total refund balance of the first currency.
     * @return amount1 The total refund balance of the second currency.
     * @return stableAmount The total refund balance of the stable currency.
     */
    function refundBalance()
        external
        view
        returns (uint256 amount0, uint256 amount1, uint256 stableAmount);
}
