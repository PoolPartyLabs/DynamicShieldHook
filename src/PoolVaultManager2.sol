// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {ECDSAServiceManagerBase} from "@eigenlayer-middleware/src/unaudited/ECDSAServiceManagerBase.sol";
import {ECDSAStakeRegistry} from "@eigenlayer-middleware/src/unaudited/ECDSAStakeRegistry.sol";
import {IServiceManager} from "@eigenlayer-middleware/src/interfaces/IServiceManager.sol";
import {ECDSAUpgradeable} from "@openzeppelin-upgrades/contracts/utils/cryptography/ECDSAUpgradeable.sol";
import {IERC1271Upgradeable} from "@openzeppelin-upgrades/contracts/interfaces/IERC1271Upgradeable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@eigenlayer/contracts/interfaces/IRewardsCoordinator.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract PoolVaultManager2 is ECDSAServiceManagerBase {
    using ECDSAUpgradeable for bytes32;

    uint256 public removeIndex;
    mapping(uint256 removeIndex => mapping(bytes32 poolId => uint256[] tokenIds))
        public reomvedTokenIds;
    uint256[] public tokenIds;

    uint32 public latestTaskNum;
    // mapping of task indices to all tasks hashes
    // when a task is created, task hash is stored here,
    // and responses need to pass the actual task,
    // which is hashed onchain and checked against this mapping
    mapping(uint32 => bytes32) public allTaskHashes;

    // mapping of task indices to hash of abi.encode(taskResponse, taskResponseMetadata)
    mapping(address => mapping(uint32 => bytes)) public allTaskResponses;

    struct Task {
        uint32 taskIndex;
        bytes32 poolId;
        uint32 taskCreatedBlock;
    }

    event TickEvent(
        bytes32 indexed poolId,
        int24 indexed currentTick,
        uint32 indexed taskIndex,
        Task task
    );

    event TaskResponded(
        uint32 indexed taskIndex,
        Task task,
        address indexed operator
    );

    event RegisterShieldEvent(
        bytes32 poolId,
        int24 feeMaxLow,
        int24 feeMaxUpper,
        uint256 tokenId,
        address owner
    );

    modifier onlyOperator() {
        require(
            // @todo review why is not working on nitro test node
            ECDSAStakeRegistry(stakeRegistry).operatorRegistered(msg.sender),
            "Operator must be the caller"
        );
        _;
    }

    constructor(
        address _avsDirectory,
        address _stakeRegistry,
        address _rewardsCoordinator,
        address _delegationManager
    )
        ECDSAServiceManagerBase(
            _avsDirectory,
            _stakeRegistry,
            _rewardsCoordinator,
            _delegationManager
        )
    {}

    function registerShield(
        bytes32 poolId,
        int24 feeMaxLow,
        int24 feeMaxUpper,
        uint256 tokenId,
        address owner
    ) external {
        emit RegisterShieldEvent(
            poolId,
            feeMaxLow,
            feeMaxUpper,
            tokenId,
            owner
        );
    }

    function sendTickEvent(bytes32 poolId, int24 currentTick) external {
        Task memory newTask;
        newTask.poolId = poolId;
        newTask.taskIndex = latestTaskNum;
        newTask.taskCreatedBlock = uint32(block.number);

        // store hash of task onchain, emit event, and increase taskNum
        allTaskHashes[latestTaskNum] = keccak256(abi.encode(newTask));
        emit TickEvent(poolId, currentTick, latestTaskNum, newTask);
        latestTaskNum++;
    }

    function removeLiquidityInBatch(
        Task calldata task,
        uint32 referenceTaskIndex,
        uint256[] memory _tokenIds,
        bytes memory signature
    ) external {
        // check that the task is valid, hasn't been responsed yet, and is being responded in time
        require(
            keccak256(abi.encode(task)) == allTaskHashes[referenceTaskIndex],
            "supplied task does not match the one recorded in the contract"
        );
        require(
            allTaskResponses[msg.sender][referenceTaskIndex].length == 0,
            "Operator has already responded to the task"
        );

        // @todo review why is not working on nitro test node

        // The message that was signed
        // bytes32 messageHash = keccak256(abi.encodePacked(task.poolId));
        // bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();
        // bytes4 magicValue = IERC1271Upgradeable.isValidSignature.selector;
        // if (
        //     !(magicValue ==
        //         ECDSAStakeRegistry(stakeRegistry).isValidSignature(
        //             ethSignedMessageHash,
        //             signature
        //         ))
        // ) {
        //     revert();
        // }

        for (uint256 i = 0; i < _tokenIds.length; i++) {
            tokenIds.push(_tokenIds[i]);
            reomvedTokenIds[removeIndex][task.poolId].push(_tokenIds[i]);
        }
        removeIndex++;

        // updating the storage with task responses
        allTaskResponses[msg.sender][referenceTaskIndex] = signature;

        // emitting event
        emit TaskResponded(referenceTaskIndex, task, msg.sender);
    }

    function getRemoveIndex() external view returns (uint256) {
        return removeIndex;
    }

    function getRemovedTokenIds(
        uint256 index,
        bytes32 poolId
    ) external view returns (uint256[] memory) {
        return reomvedTokenIds[index][poolId];
    }

    function getTokenIds() external view returns (uint256[] memory) {
        return tokenIds;
    }
}
