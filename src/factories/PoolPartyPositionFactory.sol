// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {PoolPartyPosition, PoolPartyPositionStorage, IPoolPartyPositionStructs} from "../PoolPartyPosition.sol";
import {Errors} from "../interfaces/Errors.sol"; 
import {IFeesVaultManagerFactory} from "../interfaces/IFeesVaultManagerFactory.sol";
import {IRefundVaultManagerFactory} from "../interfaces/IRefundVaultManagerFactory.sol";
import {ISnapshotManagerFactory} from "../interfaces/ISnapshotManagerFactory.sol";
import {IPoolPartyPositionViewFactory} from "../interfaces/IPoolPartyPositionViewFactory.sol";
import "../interfaces/IPoolPartyPositionFactory.sol";
import "../interfaces/Constants.sol";

/**
 * @title PoolPartyPositionFactory Contract
 * @notice This contract is used to create and manage PoolPartyPosition contracts.
 * It handles the creation, pausing, unpausing, and destruction of PoolPartyPosition contracts.
 */
contract PoolPartyPositionFactory is
    IPoolPartyPositionFactory,
    AccessControlDefaultAdminRules,
    Pausable,
    ReentrancyGuard
{
    using PositionIdLib for PositionKey;

    UpgradeableBeacon private immutable i_upgradeableBeacon;
    IFeesVaultManagerFactory private immutable i_feesVaultManagerFactory;
    ISnapshotManagerFactory private immutable i_snapshotManagerFactory;
    IRefundVaultManagerFactory private immutable i_refundVaultManagerFactory;
    IPoolPartyPositionViewFactory
        private immutable i_poolPartyPositionViewFactory;
    mapping(PositionId => address proxy) private s_proxies;
    mapping(bytes32 hashedName => bool) private s_poolPositionNames;
    bool public s_destroyed;

    modifier whenNotDestroyed() {
        require(!s_destroyed, Errors.IsDestroyed());
        _;
    }

    // slither-disable-next-line incorrect-modifier
    modifier onlyAdminOrManager() {
        _checkAdminOrManager();
        _;
    }

    // slither-disable-start incorrect-modifier
    // aderyn-ignore-next-line(useless-modifier)
    modifier onlyPoolPositionNameNotExist(string memory _name) {
        bytes32 hashedName = keccak256(abi.encodePacked(_name));
        require(
            !s_poolPositionNames[hashedName],
            Errors.PoolPositionNameExists()
        );
        _;
    }

    // slither-disable-end incorrect-modifier

    constructor(
        ConstructParams memory _params
    ) AccessControlDefaultAdminRules(5 days, _params.admin) {
        i_upgradeableBeacon = new UpgradeableBeacon(
            address(new PoolPartyPosition()),
            address(this)
        );
        i_feesVaultManagerFactory = IFeesVaultManagerFactory(
            _params.feesVaultManagerFactory
        );
        i_snapshotManagerFactory = ISnapshotManagerFactory(
            _params.snapshotManagerFactory
        );
        i_refundVaultManagerFactory = IRefundVaultManagerFactory(
            _params.refundVaultManagerFactory
        );
        i_poolPartyPositionViewFactory = IPoolPartyPositionViewFactory(
            _params.poolPartyPositionViewFactory
        );
        _grantRole(UPGRADER_ROLE, _params.upgrader);
        _grantRole(PAUSER_ROLE, _params.pauser);
        _grantRole(DESTROYER_ROLE, _params.destroyer);
    }

    /**
     * @notice Pauses the contract.
     */
    function pause()
        external
        onlyRole(PAUSER_ROLE) // aderyn-ignore(centralization-risk)
        whenNotDestroyed
        whenNotPaused
    {
        _pause();
    }

    /**
     * @notice Unpauses the contract.
     */
    function unpause()
        external
        onlyRole(PAUSER_ROLE) // aderyn-ignore(centralization-risk)
        whenNotDestroyed
        whenPaused
    {
        _unpause();
    }

    /**
     * @notice Destroys the contract.
     */
    function destroy()
        external
        onlyRole(DESTROYER_ROLE) // aderyn-ignore(centralization-risk)
        whenNotDestroyed
    {
        s_destroyed = true;
        emit Destroyed();
    }

    /**
     * @notice Sets the manager of the contract.
     * @param _manager The address of the manager.
     */
    function setManager(
        address _manager
    )
        external
        onlyRole(DEFAULT_ADMIN_ROLE) // aderyn-ignore(centralization-risk)
    {
        require(_manager != address(0), Errors.AddressIsZero());
        _grantRole(MANAGER_ROLE, _manager);
    }

    /**
     * @notice Creates a new PoolPartyPosition contract.
     * @param _params The parameters required to create the position.
     * @return poolPosition The address of the created PoolPartyPosition contract.
     */
    // aderyn-ignore-next-line(state-variable-changes-without-events)
    function create(
        IPoolPartyPositionStructs.ConstructorParams calldata _params
    )
        external
        nonReentrant
        onlyAdminOrManager
        onlyPoolPositionNameNotExist(_params.name)
        returns (IPoolPartyPosition poolPosition)
    {
        address pool = IUniswapV3Factory(_params.uniswapV3Factory).getPool(
            _params.currency0,
            _params.currency1,
            _params.fee
        );
        bytes32 hashedName = keccak256(abi.encodePacked(_params.name));
        PositionKey memory positionKey = PositionKey({
            pool: pool,
            operator: _params.operator,
            operatorFee: _params.operatorFee,
            currency0: _params.currency0,
            currency1: _params.currency1,
            fee: _params.fee,
            tickLower: _params.tickLower,
            tickUpper: _params.tickUpper,
            name: hashedName
        });
        s_poolPositionNames[hashedName] = true;
        PositionId positionId = positionKey.toId();

        poolPosition = IPoolPartyPosition(s_proxies[positionId]);
        if (address(poolPosition) != address(0)) {
            require(
                poolPosition.poolPositionView().isClosed(),
                Errors.PoolPositionNotClosed()
            );
        }

        bytes memory data = abi.encodeWithSelector(
            PoolPartyPositionStorage.initialize.selector,
            _params,
            address(this)
        );
        BeaconProxy proxy = new BeaconProxy(address(i_upgradeableBeacon), data);
        poolPosition = IPoolPartyPosition(address(proxy));
        // slither-disable-next-line reentrancy-no-eth
        s_proxies[positionId] = address(poolPosition);

        address poolPositionView = address(
            IPoolPartyPositionViewFactory(i_poolPartyPositionViewFactory)
                .create(address(poolPosition))
        );
        poolPosition.setupPoolPositionView(poolPositionView);

        address refundVaultManager = i_refundVaultManagerFactory.create(
            address(poolPosition),
            _params.currency0,
            _params.currency1,
            _params.stableCurrency
        );
        address snapshotManager = i_snapshotManagerFactory.create(
            address(poolPosition)
        );
        address feesVaultManager = i_feesVaultManagerFactory.create(
            address(poolPosition),
            _params.currency0,
            _params.currency1,
            _params.stableCurrency
        );
        poolPosition.setupVaultsAndSnapshotManagers(
            refundVaultManager,
            feesVaultManager,
            snapshotManager
        );
    }

    /**
     * @notice Upgrades the implementation of the beacon.
     * @param _impl The address of the new implementation.
     */
    function upgradeTo(
        address _impl
    )
        external
        onlyRole(UPGRADER_ROLE) // aderyn-ignore(centralization-risk)
    {
        i_upgradeableBeacon.upgradeTo(_impl);
    }

    /**
     * @notice Retrieves the implementation address of the beacon.
     * @return The address of the implementation.
     */
    function getImplementation()
        external
        view
        onlyAdminOrManager
        returns (address)
    {
        return i_upgradeableBeacon.implementation();
    }

    /**
     * @notice Retrieves the proxy address for a given position ID.
     * @param _positionId The ID of the position.
     * @return The address of the proxy.
     */
    function getProxy(
        PositionId _positionId
    ) external view onlyAdminOrManager returns (address) {
        return s_proxies[_positionId];
    }

    /**
     * @notice Updates the proxy address for a given position ID.
     * @param _oldPositionId The old position ID.
     * @param _newPositionId The new position ID.
     * @return The address of the updated proxy.
     */
    // aderyn-ignore-next-line(state-variable-changes-without-events)
    function updatePoolPartyPosition(
        PositionId _oldPositionId,
        PositionId _newPositionId
    ) external onlyAdminOrManager returns (address) {
        s_proxies[_newPositionId] = s_proxies[_oldPositionId];
        return s_proxies[_newPositionId];
    }

    /**
     * @notice Retrieves the PoolPartyPosition contract for a given position ID.
     * @param _positionId The ID of the position.
     * @return The address of the PoolPartyPosition contract.
     */
    function getPoolPartyPosition(
        PositionId _positionId
    ) external view onlyAdminOrManager returns (IPoolPartyPosition) {
        return IPoolPartyPosition(s_proxies[_positionId]);
    }

    /**
     * @notice Checks if the caller is an admin or manager.
     */
    function _checkAdminOrManager() private view {
        if (
            !hasRole(DEFAULT_ADMIN_ROLE, _msgSender()) &&
            !hasRole(MANAGER_ROLE, _msgSender())
        ) {
            revert Errors.Unauthorized();
        }
    }
}
