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
        tokenId = _initShield();
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

        s_shieldHook.addLiquidty(key, tokenId, amount0Desired, amount1Desired);

        uint128 newLiquidity = s_shieldHook.getPositionLiquidity(tokenId);
        assertEq(newLiquidity, 168847254834177964578369);
        vm.stopPrank();
    }

    function test_removeLiquidty() public {
        test_addLiquidty();

        vm.startPrank(alice);
        s_shieldHook.removeLiquidity(
            key,
            tokenId,
            50e4 // 50%
        );
        uint128 newLiquidity = s_shieldHook.getPositionLiquidity(tokenId);
        assertEq(newLiquidity, 84423627417088982289185);
        vm.stopPrank();
    }

    function test_swapMulti() public {
        tokenId = _initShield();
        MockERC20(Currency.unwrap(currency0)).mint(alice, 1000000000e18);
        MockERC20(Currency.unwrap(currency1)).mint(alice, 1000000000e18);
        MockERC20(Currency.unwrap(currency0)).mint(
            address(this),
            1000000000e18
        );
        MockERC20(Currency.unwrap(currency1)).mint(
            address(this),
            1000000000e18
        );
        MockERC20(Currency.unwrap(stableCoin)).mint(alice, 1000000000e18);
        MockERC20(Currency.unwrap(stableCoin)).mint(
            address(this),
            1000000000e18
        );

        // // some liquidity for full range
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: TickMath.minUsableTick(60),
                tickUpper: TickMath.maxUsableTick(60),
                liquidityDelta: 2000000000e18,
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );
        uint256 numOfKeys = 10;
        PoolKey[] memory pools = new PoolKey[](numOfKeys);
        int256[] memory amounts = new int256[](numOfKeys);

        assertEq(
            1671754998358197669092,
            s_shieldHook.getPositionLiquidity(tokenId)
        );
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
        for (uint256 i = 0; i < numOfKeys; i++) {
            pools[i] = key;
            if (i % 2 == 0) {
                amounts[i] = 100e18;
            } else {
                amounts[i] = -100e18;
            }
        }
        _swapMulti(pools, amounts);

        assertEq(
            1671754998358197669092,
            s_shieldHook.getPositionLiquidity(tokenId)
        );
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
    }

    function _initShield() internal returns (uint256) {
        vm.startPrank(alice);
        IERC20(address(USDC)).approve(address(s_shieldHook), type(uint256).max);
        IERC20(Currency.unwrap(token0)).approve(
            address(s_shieldHook),
            type(uint256).max
        );
        IERC20(Currency.unwrap(token1)).approve(
            address(s_shieldHook),
            type(uint256).max
        );

        uint256 amount0Desired = 10e18;
        uint256 amount1Desired = 10e18;

        uint256 _tokenId = s_shieldHook.initializeShield(
            key,
            mapToAddLiquidityParams(
                SQRT_PRICE_1_1,
                LIQUIDITY_PARAMS.tickLower,
                LIQUIDITY_PARAMS.tickUpper,
                amount0Desired,
                amount1Desired
            ),
            amount0Desired,
            amount1Desired
        );

        console.log(
            "getPositionLiquidity: ",
            s_shieldHook.getPositionLiquidity(_tokenId)
        );
        assertEq(s_shieldHook.ownerOf(_tokenId), alice);
        vm.stopPrank();
        return _tokenId;
    }
}
