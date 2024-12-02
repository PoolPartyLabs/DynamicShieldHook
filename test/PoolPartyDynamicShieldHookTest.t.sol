// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./TestHelper.t.sol";

contract PoolPartyDynamicShieldHookTest is TestHelper {
    // Use the libraries
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using Planner for Plan;
    using BipsLibrary for uint256;

    function test_initializeShieldTokenHolder() public {
        _initShield();
        assertEq(lpm.ownerOf(tokenId), s_shieldHook.getVaulManagerAddress());
    }

    function test_addLiquidty() public {
        test_initializeShieldTokenHolder();

        vm.startPrank(alice);
        uint256 amount0Desired = 1000e18;
        uint256 amount1Desired = 1000e18;

        IERC20(Currency.unwrap(token0)).approve(
            address(s_shieldHook),
            amount0Desired
        );
        IERC20(Currency.unwrap(token1)).approve(
            address(s_shieldHook),
            amount1Desired
        );

        s_shieldHook.addLiquidty(
            key,
            tokenId,
            amount0Desired,
            amount1Desired,
            block.timestamp + 1000
        );

        uint128 newLiquidity = lpm.getPositionLiquidity(tokenId);
        assertEq(newLiquidity, 333515122172460434984007);
        vm.stopPrank();
    }

    function test_removeLiquidty() public {
        test_addLiquidty();

        vm.startPrank(alice);
        s_shieldHook.removeLiquidity(
            key,
            tokenId,
            50e4,
            block.timestamp + 1000
        );
        uint128 newLiquidity = lpm.getPositionLiquidity(tokenId);
        assertEq(newLiquidity, 166757561086230217492004);
        vm.stopPrank();
    }

    function test_swapMulti() public {
        _initShield();
        PoolKey[] memory pools = new PoolKey[](10);
        int256[] memory amounts = new int256[](10);

        assertEq(166339622336640668074730, lpm.getPositionLiquidity(tokenId));
        assertEq(
            0,
            IERC20(Currency.unwrap(token0)).balanceOf(
                s_shieldHook.getVaulManagerAddress()
            )
        );
        assertEq(
            0,
            IERC20(Currency.unwrap(token1)).balanceOf(
                s_shieldHook.getVaulManagerAddress()
            )
        );
        assertEq(
            0,
            IERC20(Currency.unwrap(stableCoin)).balanceOf(
                s_shieldHook.getVaulManagerAddress()
            )
        );
        for (uint256 i = 0; i < 10; i++) {
            pools[i] = key;
            if (i % 2 == 0) {
                amounts[i] = 1e18 * int256(i + 1);
            } else {
                amounts[i] = -1e18 * int256(i + 2);
            }
        }
        _swapMulti(pools, amounts);

        assertEq(1663396223366406680748, lpm.getPositionLiquidity(tokenId));
        assertEq(
            0,
            IERC20(Currency.unwrap(token0)).balanceOf(
                s_shieldHook.getVaulManagerAddress()
            )
        );
        assertEq(
            0,
            IERC20(Currency.unwrap(token1)).balanceOf(
                s_shieldHook.getVaulManagerAddress()
            )
        );
        assertEq(
            2999999972,
            IERC20(Currency.unwrap(stableCoin)).balanceOf(
                s_shieldHook.getVaulManagerAddress()
            )
        );
    }

    function _initShield() internal {
        vm.startPrank(alice);
        IERC721(address(lpm)).approve(address(s_shieldHook), tokenId);
        uint24 _feeInit = 3000;
        uint24 _feeMax = 3000;
        PoolPartyDynamicShieldHook.TickSpacing _tickSpacing = PoolPartyDynamicShieldHook
                .TickSpacing
                .Low;

        s_shieldHook.initializeShieldTokenHolder(
            key,
            stableCoin,
            _tickSpacing,
            _feeInit,
            _feeMax,
            tokenId
        );
        vm.stopPrank();
    }
}
