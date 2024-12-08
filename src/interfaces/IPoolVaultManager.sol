// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IPoolModifyLiquidity} from "../interfaces/IPoolModifyLiquidity.sol";

interface IPoolVaultManager {
    struct Position {
        PoolKey key;
        address owner;
        uint256 tokenId;
    }

    struct PositionTotalSupply {
        PoolKey key;
        uint256 tokenId;
        uint256 amount0;
        uint256 amount1;
    }

    struct CallData {
        PoolKey key;
        address owner;
    }

    struct CallbackUnlockData {
        bool modifyLiquidity;
        bytes unlockData;
    }

    error InvalidPositionManager();
    error InvalidHook();
    error InvalidSelf();

    function mint(
        PoolKey calldata _poolKey,
        IPoolManager.ModifyLiquidityParams memory _params,
        address _owner,
        uint256 _amount0Desired,
        uint256 _amount1Desired
    ) external returns (uint256 tokenId);

    function addLiquidity(
        PoolKey memory _key,
        uint256 _tokenId,
        address _owner,
        uint256 _amount0Desired,
        uint256 _amount1Desired
    ) external;

    function removeLiquidity(
        PoolKey memory _key,
        uint256 _tokenId,
        uint128 _percentage,
        address _owner
    ) external returns (uint256 amount0, uint256 amount1);

    function collectFees(
        PoolKey memory _key,
        uint256 _tokenId,
        address _owner
    ) external returns (uint256 fees0, uint256 fees1);

    function removeLiquidityInBatch(
        PoolId poolId,
        uint256[] calldata _tokenIds,
        bool _withoutUnlock
    ) external;

    function getTotalSupplies(
        PoolKey calldata _key,
        uint256[] calldata _tokenIds
    ) external view returns (PositionTotalSupply[] memory totalSupplies);

    function getPoolAndPositionInfo(
        uint256 tokenId
    )
        external
        view
        returns (
            PoolKey memory poolKey,
            IPoolModifyLiquidity.PositionInfo memory
        );

    function getPositionLiquidity(
        uint256 tokenId
    ) external view returns (uint128 liquidity);

    function ownerOf(uint256 tokenId) external view returns (address owner);
}
