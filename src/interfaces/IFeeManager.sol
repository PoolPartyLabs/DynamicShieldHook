// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IFeeManager {
    function getFee(bytes32 pool_id, int32 tick) external view returns (uint32);

    function updateFeePerTick(
        bytes32 pool_id,
        uint128 liquidity,
        int32 tick_lower,
        int32 tick_upper,
        uint32 tick_spacing,
        uint32 fee_init,
        uint32 fee_max
    ) external;
}
