// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IDynamicShieldAVS} from "../../src/eigenlayer/IDynamicShieldAVS.sol";

contract DynamicShieldAVS is IDynamicShieldAVS {
    function notifyRegisterShield(
        bytes32 poolId,
        int24 tickLower,
        int24 tickUpper,
        uint256 tokenId
    ) external {}

    function notifyTickEvent(bytes32 poolId, int24 currentTick) external {}

    function respondToTask(
        Task calldata task,
        uint32 referenceTaskIndex,
        uint256[] memory _tokenIds,
        bytes memory signature
    ) external {}
}
