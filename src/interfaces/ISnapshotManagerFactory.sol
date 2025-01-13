// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

/**
 * @title SnapshotManagerFactory Interface
 */
interface ISnapshotManagerFactory {
    function create(address _owner) external returns (address snapshotManager);
}
