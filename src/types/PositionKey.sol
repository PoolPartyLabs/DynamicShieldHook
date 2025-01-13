// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

/// @notice Returns the key for identifying a position
struct PositionKey {
    address pool;
    address operator;
    address currency0;
    address currency1;
    uint24 operatorFee;
    uint24 fee;
    int24 tickLower;
    int24 tickUpper;
    bytes32 name;
}
