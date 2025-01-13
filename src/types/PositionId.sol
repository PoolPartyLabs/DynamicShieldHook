// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {PositionKey} from "./PositionKey.sol";

type PositionId is bytes32;

/// @notice Library for computing the ID of a Position
library PositionIdLib {
    /// @notice Returns value equal to keccak256(abi.encode(positionKey))
    function toId(PositionKey memory positionKey) internal pure returns (PositionId positionId) {
        assembly ("memory-safe") {
            positionId := keccak256(positionKey, mul(32, 9))
        }
    }
}
