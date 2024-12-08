// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IFeeManager} from "../../src/interfaces/IFeeManager.sol";

contract FeeManager is IFeeManager {
    function getFee(bytes32, int32) external pure returns (uint32) {
        return 100;
    }

    function updateFeePerTick(
        bytes32 pool_id,
        uint128 liquidity,
        int32 tick_lower,
        int32 tick_upper,
        uint32 tick_spacing,
        uint32 fee_init,
        uint32 fee_max
    ) external {}
}
