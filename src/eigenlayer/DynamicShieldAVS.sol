// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/** EigenLayer Contracts */
import {ECDSAServiceManagerBase} from "@eigenlayer-middleware/src/unaudited/ECDSAServiceManagerBase.sol";
import {ECDSAStakeRegistry} from "@eigenlayer-middleware/src/unaudited/ECDSAStakeRegistry.sol";

/** OpenZeppelin Contracts */
import {ECDSAUpgradeable} from "@openzeppelin-upgrades/contracts/utils/cryptography/ECDSAUpgradeable.sol";
import {IERC1271Upgradeable} from "@openzeppelin-upgrades/contracts/interfaces/IERC1271Upgradeable.sol";

/** Uniswap v4 Core */
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";

/** Internal */
import {IPoolPartyDynamicShieldHook} from "../interfaces/IPoolPartyDynamicShieldHook.sol";
import {IDynamicShieldAVS} from "./IDynamicShieldAVS.sol";

contract DynamicShieldAVS is IDynamicShieldAVS, ECDSAServiceManagerBase {
    using ECDSAUpgradeable for bytes32;
    using PoolIdLibrary for bytes32;

    address s_poolPartyDynamicShieldHook;
    uint32 public s_latestTaskNum;

    // mapping of task indices to all tasks hashes
    // when a task is created, task hash is stored here,
    // and responses need to pass the actual task,
    // which is hashed onchain and checked against this mapping
    mapping(uint32 => bytes32) public s_allTaskHashes;

    // mapping of task indices to hash of abi.encode(taskResponse, taskResponseMetadata)
    mapping(address => mapping(uint32 => bytes)) public s_allTaskResponses;

    modifier onlyOperator() {
        // require(
        //     // @todo review why is not working on nitro test node
        //     ECDSAStakeRegistry(stakeRegistry).operatorRegistered(msg.sender),
        //     "Operator must be the caller"
        // );
        _;
    }

    modifier onlyHook() {
        // require(
        //     msg.sender == address(s_poolPartyDynamicShieldHook),
        //     "Caller must be the hook"
        // );
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
    {
    }

    function setPoolPartyDynamicShieldHook(address _hook) external {
        s_poolPartyDynamicShieldHook = _hook;
    }

    function notifyRegisterShield(
        bytes32 poolId,
        int24 tickLower,
        int24 tickUpper,
        uint256 tokenId
    ) external onlyHook {
        emit RegisterShieldEvent(poolId, tickLower, tickUpper, tokenId);
    }

    function notifyTickEvent(
        bytes32 poolId,
        int24 currentTick
    ) external onlyHook {
        Task memory newTask;
        newTask.poolId = poolId;
        newTask.taskIndex = s_latestTaskNum;
        newTask.taskCreatedBlock = uint32(block.number);

        // store hash of task onchain, emit event, and increase taskNum
        s_allTaskHashes[s_latestTaskNum] = keccak256(abi.encode(newTask));
        emit TickEvent(poolId, currentTick, s_latestTaskNum, newTask);
        s_latestTaskNum++;
    }

    function respondToTask(
        Task calldata task,
        uint32 referenceTaskIndex,
        uint256[] calldata _tokenIds,
        bytes calldata signature
    ) external onlyOperator {
        // check that the task is valid, hasn't been responsed yet, and is being responded in time
        require(
            keccak256(abi.encode(task)) == s_allTaskHashes[referenceTaskIndex],
            "supplied task does not match the one recorded in the contract"
        );
        require(
            s_allTaskResponses[msg.sender][referenceTaskIndex].length == 0,
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

        s_allTaskResponses[msg.sender][referenceTaskIndex] = signature;

        if (s_poolPartyDynamicShieldHook != address(0)) {
            IPoolPartyDynamicShieldHook(s_poolPartyDynamicShieldHook)
                .removeLiquidityInBatch(PoolId.wrap(task.poolId), _tokenIds);
        } else {
            revert("DynamicShieldAVS: hook not set");
        }

        emit TaskResponded(referenceTaskIndex, task, msg.sender);
    }
}
