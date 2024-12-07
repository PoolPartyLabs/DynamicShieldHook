// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

interface IPoolPartyDynamicShieldHook is IHooks {
    struct TickInfo {
        PoolId poolId;
        int24 tick;
        uint128 liquidity;
        uint24 fee;
    }

    struct CallData {
        PoolKey key;
    }

    struct ShieldInfo {
        uint256 tokenId;
    }

    enum TickSpacing {
        Invalid, // 0
        Low, // 10
        Medium, // 60
        High // 200
    }

    // Errors
    error MustUseDynamicFee();
    error InvalidTickSpacing();
    error InvalidPositionManager();
    error InvalidSelf();
    error InvalidAVS();

    function setAVS(address _avs) external;

    function initializeShield(
        PoolKey calldata _poolKey,
        uint256 _tokenId
    ) external;

    function addLiquidty(
        PoolKey calldata _poolKey,
        uint256 _tokenId,
        uint256 _amount0,
        uint256 _amount1,
        uint256 _deadline
    ) external;

    function removeLiquidity(
        PoolKey memory _poolKey,
        uint256 _tokenId,
        uint128 _percentage,
        uint256 _deadline
    ) external;

    function collectFees(
        PoolKey memory _key,
        uint256 _tokenId,
        uint256 _deadline
    ) external;

    function removeLiquidityInBatch(
        PoolId _poolId,
        uint256[] memory _tokenIds
    ) external;

    function getVaulManagerAddress() external view returns (address);
}
