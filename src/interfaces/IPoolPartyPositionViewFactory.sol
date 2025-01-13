// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IPoolPartyPositionView} from "./IPoolPartyPositionView.sol";

/**
 * @title IPoolPartyPositionViewFactory Interface
 */
interface IPoolPartyPositionViewFactory {
    struct ConstructParams {
        address admin;
        address upgrader;
        address pauser;
    }

    /**
     * @notice Pauses the contract.
     */
    function pause() external;

    /**
     * @notice Unpauses the contract.
     */
    function unpause() external;

    /**
     * @notice Creates a new PoolPartyPositionView contract.
     * @param _poolPosition The address of the PoolPartyPosition contract.
     * @return poolPositionView The address of the created PoolPartyPositionView contract.
     */
    function create(
        address _poolPosition
    ) external returns (IPoolPartyPositionView poolPositionView);

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
     * @notice Retrieves the proxy address for a given position address.
     * @param _position The address of the position.
     * @return The address of the proxy.
     */
    function getProxy(address _position) external view returns (address);

    /**
     * @notice Updates the proxy address for a given position address.
     * @param _oldPosition The old position address.
     * @param _newPosition The new position address.
     * @return The address of the updated proxy.
     */
    function updatePoolPartyPositionView(
        address _oldPosition,
        address _newPosition
    ) external returns (address);

    /**
     * @notice Retrieves the PoolPartyPosition contract for a given position address.
     * @param _position The address of the position.
     * @return The address of the PoolPartyPosition contract.
     */
    function getPoolPartyPositionView(
        address _position
    ) external view returns (IPoolPartyPositionView);
}
