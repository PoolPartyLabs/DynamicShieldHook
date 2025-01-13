// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

bytes32 constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
bytes32 constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
bytes32 constant DESTROYER_ROLE = keccak256("DESTROYER_ROLE");
bytes32 constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
bytes32 constant FACTORY_ROLE = keccak256("FACTORY_ROLE");
string constant EIP712_NAME = "PoolPartyPositionManager";
string constant EIP712_VERSION = "1.0.0";
uint256 constant MAX_POSITIONS = 500;
uint256 constant DENOMINATOR_MULTIPLIER = 1e18;
uint256 constant MIN_OPERATOR_FEE = 1e3;
uint256 constant MAX_OPERATOR_FEE = 10e3;
uint256 constant MIN_PROTOCOL_FEE = 1e3;
uint256 constant MAX_PROTOCOL_FEE = 10e3;
uint256 constant MIN_INVESTMENT_STABLE = 10 * 1e6;
uint256 constant REMOVE_PERCENTAGE_MULTIPLIER = 1e15;
uint256 constant MAX_INPUT_AMOUNT = 999_999_999;
uint256 constant MIN_REFUND_AMOUNT = 10;
uint24 constant FEE_DENOMINATOR = 1e4; // 10_000
uint16 constant SWAP_FEE = 9975; // 0.25% fee
uint8 constant HUNDRED_PERCENT = 100;
