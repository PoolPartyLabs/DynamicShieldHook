// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolTestBase} from "v4-core/src/test/PoolTestBase.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {LPFeeLibrary} from "v4-core/src/libraries/LPFeeLibrary.sol";
import {CurrencySettler} from "v4-core/test/utils/CurrencySettler.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {TransientStateLibrary} from "v4-core/src/libraries/TransientStateLibrary.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {SafeCallback} from "v4-periphery/src/base/SafeCallback.sol";
import {IPoolModifyLiquidity} from "../interfaces/IPoolModifyLiquidity.sol";
import {IPoolVaultManager} from "../interfaces/IPoolVaultManager.sol";

abstract contract PoolModifyLiquidity is IPoolModifyLiquidity, IUnlockCallback {
    using CurrencySettler for Currency;
    using Hooks for IHooks;
    using LPFeeLibrary for uint24;
    using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using TransientStateLibrary for IPoolManager;

    /// @dev The ID of the next token that will be minted. Skips 0
    uint256 public nextTokenId = 1;
    mapping(uint256 tokenId => PositionInfo) public positionInfo;
    IPoolManager immutable s_poolManager;

    /// @notice Thrown when calling unlockCallback where the caller is not PoolManager
    error NotPoolManager();

    /// @notice Only allow calls from the PoolManager contract
    modifier onlyPoolManager() {
        if (msg.sender != address(s_poolManager)) revert NotPoolManager();
        _;
    }

    constructor(IPoolManager _manager) {
        s_poolManager = _manager;
    }

    struct CallbackData {
        address sender;
        PoolKey key;
        IPoolManager.ModifyLiquidityParams params;
        uint256 tokenId;
        bytes hookData;
        bool settleUsingBurn;
        bool takeClaims;
    }

    function mintAndAddLiquidity(
        PoolKey memory key,
        IPoolManager.ModifyLiquidityParams memory params,
        address recipient,
        bytes memory hookData
    ) internal returns (BalanceDelta delta) {
        positionInfo[nextTokenId] = PositionInfo(
            key,
            recipient,
            nextTokenId,
            params.tickLower,
            params.tickUpper,
            uint256(0)
        );
        delta = modifyLiquidity(
            key,
            params,
            nextTokenId,
            recipient,
            hookData,
            false,
            false
        );
        nextTokenId++;
    }

    function modifyLiquidity(
        PoolKey memory key,
        IPoolManager.ModifyLiquidityParams memory params,
        uint256 tokenId,
        address recipient,
        bytes memory hookData
    ) internal returns (BalanceDelta delta) {
        delta = modifyLiquidity(
            key,
            params,
            tokenId,
            recipient,
            hookData,
            false,
            false
        );
    }

    function modifyLiquidity(
        PoolKey memory key,
        IPoolManager.ModifyLiquidityParams memory params,
        uint256 tokenId,
        address recipient,
        bytes memory hookData,
        bool settleUsingBurn,
        bool takeClaims
    ) internal returns (BalanceDelta delta) {
        PositionInfo memory position = positionInfo[tokenId];
        require(position.owner == recipient, "not owner");
        require(
            PoolId.unwrap(key.toId()) == PoolId.unwrap(position.key.toId()),
            "key mismatch"
        );
        if (params.liquidityDelta < 0) {
            require(
                uint256(-params.liquidityDelta) <= position.liquidity,
                "insufficient liquidity"
            );
        }
        params.salt = bytes32(tokenId);
        delta = abi.decode(
            s_poolManager.unlock(
                abi.encode(
                    IPoolVaultManager.CallbackUnlockData(
                        true,
                        abi.encode(
                            CallbackData(
                                address(this),
                                key,
                                params,
                                tokenId,
                                hookData,
                                settleUsingBurn,
                                takeClaims
                            )
                        )
                    )
                )
            ),
            (BalanceDelta)
        );
        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            CurrencyLibrary.ADDRESS_ZERO.transfer(address(this), ethBalance);
        }
    }

    function modifyLiquidityWithoutUnlock(
        PoolKey memory key,
        IPoolManager.ModifyLiquidityParams memory params,
        uint256 tokenId,
        address recipient,
        bytes memory hookData
    ) internal returns (BalanceDelta delta) {
        delta = modifyLiquidityWithoutUnlock(
            key,
            params,
            tokenId,
            recipient,
            hookData,
            false,
            false
        );
    }

    function modifyLiquidityWithoutUnlock(
        PoolKey memory key,
        IPoolManager.ModifyLiquidityParams memory params,
        uint256 tokenId,
        address recipient,
        bytes memory hookData,
        bool settleUsingBurn,
        bool takeClaims
    ) internal returns (BalanceDelta delta) {
        PositionInfo memory position = positionInfo[tokenId];
        require(position.owner == recipient, "not owner");
        require(
            PoolId.unwrap(key.toId()) == PoolId.unwrap(position.key.toId()),
            "key mismatch"
        );
        if (params.liquidityDelta < 0) {
            require(
                uint256(-params.liquidityDelta) <= position.liquidity,
                "insufficient liquidity"
            );
        }
        params.salt = bytes32(tokenId);
        delta = abi.decode(
            _unlockCallbackModifyLiquidity(
                abi.encode(
                    IPoolVaultManager.CallbackUnlockData(
                        true,
                        abi.encode(
                            CallbackData(
                                address(this),
                                key,
                                params,
                                tokenId,
                                hookData,
                                settleUsingBurn,
                                takeClaims
                            )
                        )
                    )
                )
            ),
            (BalanceDelta)
        );
        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            CurrencyLibrary.ADDRESS_ZERO.transfer(address(this), ethBalance);
        }
    }

    function _unlockCallbackModifyLiquidity(
        bytes memory rawData
    ) internal returns (bytes memory) {
        CallbackData memory data = abi.decode(rawData, (CallbackData));

        (uint128 liquidityBefore, , ) = s_poolManager.getPositionInfo(
            data.key.toId(),
            address(this),
            data.params.tickLower,
            data.params.tickUpper,
            data.params.salt
        );

        (BalanceDelta delta, ) = s_poolManager.modifyLiquidity(
            data.key,
            data.params,
            data.hookData
        );

        (uint128 liquidityAfter, , ) = s_poolManager.getPositionInfo(
            data.key.toId(),
            address(this),
            data.params.tickLower,
            data.params.tickUpper,
            data.params.salt
        );

        (, , int256 delta0) = _fetchBalances(
            data.key.currency0,
            data.sender,
            address(this)
        );
        (, , int256 delta1) = _fetchBalances(
            data.key.currency1,
            data.sender,
            address(this)
        );

        require(
            int128(liquidityBefore) + data.params.liquidityDelta ==
                int128(liquidityAfter),
            "liquidity change incorrect"
        );

        PositionInfo storage position = positionInfo[data.tokenId];
        position.liquidity = uint256(liquidityAfter);

        if (data.params.liquidityDelta < 0) {
            assert(delta0 > 0 || delta1 > 0);
            assert(!(delta0 < 0 || delta1 < 0));
        } else if (data.params.liquidityDelta > 0) {
            assert(delta0 < 0 || delta1 < 0);
            assert(!(delta0 > 0 || delta1 > 0));
        }

        if (delta0 < 0)
            data.key.currency0.settle(
                s_poolManager,
                data.sender,
                uint256(-delta0),
                data.settleUsingBurn
            );
        if (delta1 < 0)
            data.key.currency1.settle(
                s_poolManager,
                data.sender,
                uint256(-delta1),
                data.settleUsingBurn
            );
        if (delta0 > 0)
            data.key.currency0.take(
                s_poolManager,
                data.sender,
                uint256(delta0),
                data.takeClaims
            );
        if (delta1 > 0)
            data.key.currency1.take(
                s_poolManager,
                data.sender,
                uint256(delta1),
                data.takeClaims
            );

        return abi.encode(delta);
    }

    function _fetchBalances(
        Currency currency,
        address user,
        address deltaHolder
    )
        internal
        view
        returns (uint256 userBalance, uint256 poolBalance, int256 delta)
    {
        userBalance = currency.balanceOf(user);
        poolBalance = currency.balanceOf(address(s_poolManager));
        delta = s_poolManager.currencyDelta(deltaHolder, currency);
    }
}
