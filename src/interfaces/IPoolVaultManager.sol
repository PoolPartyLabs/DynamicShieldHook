// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";

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

    error InvalidPositionManager();
    error InvalidHook();
    error InvalidSelf();

    function depositPosition(
        PoolKey calldata _key,
        uint256 _tokenId,
        address _owner
    ) external payable;

    function mint() external;

    function addLiquidity(
        PoolKey memory _key,
        uint256 _tokenId,
        uint256 _amount0,
        uint256 _amount1,
        uint256 _deadline
    ) external;

    function removeLiquidity(
        PoolKey memory _key,
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
        PoolId poolId,
        uint256[] calldata _tokenIds
    ) external;

    function getTotalSupplies(
        PoolKey calldata _key,
        uint256[] calldata _tokenIds
    ) external view returns (PositionTotalSupply[] memory totalSupplies);
}
