// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IPoolModifyLiquidity} from "../interfaces/IPoolModifyLiquidity.sol";

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

    event AVSRegistered(address indexed avs);

    function registerAVS(address _avs) external;

    function initializeShield(
        PoolKey calldata _poolKey,
        IPoolManager.ModifyLiquidityParams memory _params,
        uint256 _amount0Desired,
        uint256 _amount1Desired
    ) external returns (uint256 tokenId);

    function addLiquidty(
        PoolKey calldata _poolKey,
        uint256 _tokenId,
        uint256 _amount0,
        uint256 _amount1
    ) external;

    function removeLiquidity(
        PoolKey memory _poolKey,
        uint256 _tokenId,
        uint128 _percentage
    ) external;

    function collectFees(
        PoolKey memory _key,
        uint256 _tokenId
    ) external;

    function removeLiquidityInBatch(
        PoolId _poolId,
        uint256[] memory _tokenIds
    ) external;

    function getVaulManagerAddress() external view returns (address);

    function getPoolAndPositionInfo(
        uint256 tokenId
    )
        external
        view
        returns (
            PoolKey memory poolKey,
            IPoolModifyLiquidity.PositionInfo memory info
        );

    function getPositionLiquidity(
        uint256 tokenId
    ) external view returns (uint128 liquidity);

     function ownerOf(uint256 _tokenId) external view returns (address owner);
}
