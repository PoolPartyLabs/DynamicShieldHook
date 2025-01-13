// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

interface ISnapshotManagerEvents {
    /**
     * @notice Emitted when a position snapshot is taken
     * @param positionSnapshotIndex  The index of the position snapshot
     * @param liquidity  The liquidity of the position
     * @param lastRewardIndex0  The last reward index of currency0
     * @param lastRewardIndex1  The last reward index of currency1
     */
    // aderyn-ignore-next-line(unindexed-events)
    event PositionSnapshotTaken(
        uint256 indexed positionSnapshotIndex,
        uint128 liquidity,
        uint256 lastRewardIndex0,
        uint256 lastRewardIndex1
    );

    /**
     * @notice Emitted when an investor snapshot is taken
     * @param investor  The address of the investor
     * @param liquidity  The liquidity of the investor
     * @param lastIndex0  The last reward index of currency0
     * @param lastIndex1  The last reward index of currency1
     * @param fees0  The accumulated fees of currency0
     * @param fees1  The accumulated fees of currency1
     */
    // aderyn-ignore-next-line(unindexed-events)
    event InvestorSnapshotTaken(
        address indexed investor,
        uint128 liquidity,
        uint256 lastIndex0,
        uint256 lastIndex1,
        uint256 fees0,
        uint256 fees1
    );

    /**
     * @notice Emitted when an investor is synced
     * @param investor  The address of the investor
     * @param liquidity  The liquidity of the investor
     * @param fees0  The accumulated fees of currency0
     * @param fees1  The accumulated fees of currency1
     * @param positionSnapshotIndex  The index of the position snapshot
     */
    // aderyn-ignore-next-line(unindexed-events)
    event InvestorSynced(
        address indexed investor,
        uint128 liquidity,
        uint256 fees0,
        uint256 fees1,
        uint256 positionSnapshotIndex
    );
}

interface ISnapshotManagerStructs {
    struct PositionState {
        uint128 liquidity;
        uint256 lastRewardIndex0;
        uint256 lastRewardIndex1;
        uint256 accumulatedFees0;
        uint256 accumulatedFees1;
        bool afterMoveRange;
    }

    struct Percentage {
        uint256 positionSnapshotIndex;
        uint256 percentage;
    }

    struct InvestorState {
        uint128 liquidity;
        uint256 lastIndex0;
        uint256 lastIndex1;
        uint256 fees0;
        uint256 fees1;
        bool synced;
        uint256 lastPositionSnapshotIndex;
        Percentage[] percentages;
    }
}

interface ISnapshotManager is ISnapshotManagerStructs, ISnapshotManagerEvents {
    /**
     * @notice Takes a snapshot of the position.
     * @param _lastRewardIndex0 The last reward index for token0.
     * @param _lastRewardIndex1 The last reward index for token1.
     * @param _liquidity The liquidity of the position.
     * @param _afterMoveRange Whether the snapshot is taken after moving the range.
     * @return The index of the taken snapshot.
     */
    function takePositionSnapshot(
        uint256 _lastRewardIndex0,
        uint256 _lastRewardIndex1,
        uint128 _liquidity,
        bool _afterMoveRange
    ) external returns (uint256);

    /**
     * @notice Takes a snapshot of the investor's state.
     * @param investor The address of the investor.
     * @param _liquidity The liquidity of the investor.
     * @param _fees0 The fees for token0.
     * @param _fees1 The fees for token1.
     * @param _lastIndex0 The last index for token0.
     * @param _lastIndex1 The last index for token1.
     */
    function takeInvestorSnapshot(
        address investor,
        uint128 _liquidity,
        uint256 _fees0,
        uint256 _fees1,
        uint256 _lastIndex0,
        uint256 _lastIndex1
    ) external;

    /**
     * @notice Takes a snapshot of the investor's state with a percentage.
     * @param investor The address of the investor.
     * @param _liquidity The liquidity of the investor.
     * @param _fees0 The fees for token0.
     * @param _fees1 The fees for token1.
     * @param _lastIndex0 The last index for token0.
     * @param _lastIndex1 The last index for token1.
     * @param _percentage The percentage of the snapshot.
     */
    function takeInvestorSnapshot(
        address investor,
        uint128 _liquidity,
        uint256 _fees0,
        uint256 _fees1,
        uint256 _lastIndex0,
        uint256 _lastIndex1,
        uint256 _percentage
    ) external;

    /**
     * @notice Synchronizes the investor's state.
     * @param investor The address of the investor.
     */
    function syncInvestor(address investor) external;

    /**
     * @notice Settles the percentage for a given snapshot index and investor.
     * @param _snapshotIndex The index of the snapshot.
     * @param _investor The address of the investor.
     */
    function settlePercentage(
        uint256 _snapshotIndex,
        address _investor
    ) external;

    /**
     * @notice Settles all percentages for an investor.
     * @param _investor The address of the investor.
     */
    function settleAllPercentages(address _investor) external;

    /**
     * @notice Virtually synchronizes the investor's state.
     * @param investor The address of the investor.
     * @return synced Whether the investor is synced.
     * @return newLiquidty The new liquidity of the investor.
     * @return fees0 The fees for token0.
     * @return fees1 The fees for token1.
     * @return lastIndex0 The last index for token0.
     * @return lastIndex1 The last index for token1.
     * @return percentages The percentages of the investor.
     */
    function virtualSyncInvestor(
        address investor
    )
        external
        view
        returns (
            bool synced,
            uint128 newLiquidty,
            uint256 fees0,
            uint256 fees1,
            uint256 lastIndex0,
            uint256 lastIndex1,
            Percentage[] memory percentages
        );

    /**
     * @notice Gets the snapshot of an investor.
     * @param investor The address of the investor.
     * @return The state of the investor.
     */
    function getInvestorSnapshot(
        address investor
    ) external view returns (InvestorState memory);

    /**
     * @notice Gets the current position snapshot index.
     * @return The current position snapshot index.
     */
    function getPositionSnapshotIndex() external view returns (uint256);
}
