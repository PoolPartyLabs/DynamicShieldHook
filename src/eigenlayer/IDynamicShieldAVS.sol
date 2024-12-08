// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IDynamicShieldAVS {
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
        int24 tickLower,
        int24 tickUpper,
        uint256 tokenId
    );

    function notifyRegisterShield(
        bytes32 poolId,
        int24 tickLower,
        int24 tickUpper,
        uint256 tokenId
    ) external;

    function notifyTickEvent(bytes32 poolId, int24 currentTick) external;

    function respondToTask(
        Task calldata task,
        uint32 referenceTaskIndex,
        uint256[] memory _tokenIds,
        bytes memory signature
    ) external;
}
