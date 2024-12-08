// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolKey} from "v4-core/src/types/PoolKey.sol";

interface IPoolModifyLiquidity {
    struct PositionInfo {
        PoolKey key;
        address owner;
        uint256 tokenId;
        int24 tickLower;
        int24 tickUpper;
        uint256 liquidity;
    }
}
