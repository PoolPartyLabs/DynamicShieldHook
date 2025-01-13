// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {PositionKey} from "../types/PositionKey.sol";
import {PositionId, PositionIdLib} from "../types/PositionId.sol";
import {IPoolPartyPosition, IPoolPartyPositionStructs} from "../interfaces/IPoolPartyPosition.sol";

/**
 * @title IPoolPartyPositionFactory Interface
 * @notice This interface defines the functions for creating and managing PoolPartyPosition contracts.
 */
interface IPoolPartyPositionFactory {

    struct ConstructParams {
        address admin;
        address upgrader;
        address pauser;
        address destroyer;
        address feesVaultManagerFactory;
        address refundVaultManagerFactory;
        address snapshotManagerFactory;
        address poolPartyPositionViewFactory;
    }

    /// @notice Emitted when the manager is destroyed
    event Destroyed();

    /**
     * @notice Pauses the contract.
     */
    function pause() external;

    /**
     * @notice Unpauses the contract.
     */
    function unpause() external;

    /**
     * @notice Destroys the contract.
     */
    function destroy() external;

    /**
     * @notice Creates a new PoolPartyPosition contract.
     * @param _params The parameters required to create the position.
     * @return poolPosition The address of the created PoolPartyPosition contract.
     */
    function create(IPoolPartyPositionStructs.ConstructorParams memory _params)
        external
        returns (IPoolPartyPosition poolPosition);

    /**
     * @notice Upgrades the implementation of the beacon.
     * @param _impl The address of the new implementation.
     */
    function upgradeTo(address _impl) external;

    /**
     * @notice Retrieves the implementation address of the beacon.
     * @return The address of the implementation.
     */
    function getImplementation() external view returns (address);

    /**
     * @notice Retrieves the proxy address for a given position ID.
     * @param _positionId The ID of the position.
     * @return The address of the proxy.
     */
    function getProxy(PositionId _positionId) external view returns (address);

    /**
     * @notice Updates the proxy address for a given position ID.
     * @param _oldPositionId The old position ID.
     * @param _newPositionId The new position ID.
     * @return The address of the updated proxy.
     */
    function updatePoolPartyPosition(PositionId _oldPositionId, PositionId _newPositionId) external returns (address);

    /**
     * @notice Retrieves the PoolPartyPosition contract for a given position ID.
     * @param _positionId The ID of the position.
     * @return The address of the PoolPartyPosition contract.
     */
    function getPoolPartyPosition(PositionId _positionId) external view returns (IPoolPartyPosition);
}
