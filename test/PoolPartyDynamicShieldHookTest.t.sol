// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Foundry libraries
import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";

import {PosmTestSetup} from "v4-periphery/test/shared/PosmTestSetup.sol";
import {Planner, Plan} from "v4-periphery/test/shared/Planner.sol";
import {BipsLibrary} from "v4-periphery/src/libraries/BipsLibrary.sol";
import {ActionConstants} from "v4-periphery/src/libraries/ActionConstants.sol";
import {Actions} from "v4-periphery/src/libraries/Actions.sol";

// Our contracts
import {PoolPartyDynamicShieldHook} from "../src/PoolPartyDynamicShieldHook.sol";

contract PoolPartyDynamicShieldHookTest is PosmTestSetup {
    // Use the libraries
    using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using Planner for Plan;
    using BipsLibrary for uint256;

    // The two currencies (tokens) from the pool
    Currency token0;
    Currency token1;
    MockERC20 fakeToken;

    PoolPartyDynamicShieldHook s_shieldHook;

    address alice;
    uint256 alicePK;
    address bob;

    function setUp() public {
        (alice, alicePK) = makeAddrAndKey("ALICE");
        (bob, ) = makeAddrAndKey("BOB");

        // Deploy v4 core contracts
        deployFreshManagerAndRouters();

        // Deploy two test tokens
        (token0, token1) = deployMintAndApprove2Currencies();

        // Requires currency0 and currency1 to be set in base Deployers contract.
        deployAndApprovePosm(manager);

        seedBalance(alice);
        approvePosmFor(alice);

        // Deploy our hook
        uint160 flags = uint160(
            Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_SWAP_FLAG
        );
        address hookAddress = address(flags);
        deployCodeTo(
            "PoolPartyDynamicShieldHook.sol",
            abi.encode(manager, lpm),
            hookAddress
        );
        s_shieldHook = PoolPartyDynamicShieldHook(hookAddress);

        // Initialize a pool with these two tokens
        uint256 tokenId;
        (key, tokenId) = _mintPosition(alice, s_shieldHook);

        vm.startPrank(alice);
        IERC721(address(lpm)).approve(address(s_shieldHook), tokenId);
        /**
         *
         *
         */
        uint24 _feeInit = 3000;
        uint24 _feeMax = 3000;
        PoolPartyDynamicShieldHook.TickSpacing _tickSpacing = PoolPartyDynamicShieldHook.TickSpacing.Low;
        s_shieldHook.initializeShieldTokenHolder(
            key,
            _tickSpacing,
            _feeInit,
            _feeMax,
            tokenId
        );
        vm.stopPrank();

        console.log("alice: %s", alice);
        console.log("Owner of tokenId: %s", lpm.ownerOf(tokenId));
        console.log("address(s_shieldHook): %s", address(s_shieldHook));

        assertEq(
            lpm.ownerOf(tokenId),
            address(0x797BD88499E3508CF78aeb62237e3a40053291D0)
        );

        // Add initial liquidity to the pool

        bytes32 salt = bytes32(uint256(345));

        // Some liquidity from -60 to +60 tick range
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: 10 ether,
                salt: salt
            }),
            ZERO_BYTES
        );
        console.log(
            "Liquidity after -60 to +60 tick range: %d",
            _getLiquidity(key, address(modifyLiquidityRouter), -60, 60, salt)
        );

        // Some liquidity from -120 to +120 tick range
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -120,
                tickUpper: 120,
                liquidityDelta: 10 ether,
                salt: salt
            }),
            ZERO_BYTES
        );
        console.log(
            "Liquidity after -120 to +120 tick range: %d",
            _getLiquidity(key, address(modifyLiquidityRouter), -120, 120, salt)
        );
        // some liquidity for full range
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: TickMath.minUsableTick(60),
                tickUpper: TickMath.maxUsableTick(60),
                liquidityDelta: 10 ether,
                salt: salt
            }),
            ZERO_BYTES
        );
        console.log(
            "Liquidity after -full range to +full range tick range: %d",
            _getLiquidity(
                key,
                address(modifyLiquidityRouter),
                TickMath.minUsableTick(60),
                TickMath.maxUsableTick(60),
                salt
            )
        );
    }

    function test_any() public {
        console.log("test_any");
    }

    function _getLiquidity(
        PoolKey memory _key,
        address _owner,
        int24 _tickLower,
        int24 _tickUpper,
        bytes32 _salt
    ) public view returns (uint128 liquidity) {
        (liquidity, , ) = manager.getPositionInfo(
            _key.toId(),
            _owner,
            _tickLower,
            _tickUpper,
            _salt
        );
    }

    function _mintPosition(
        address _account,
        IHooks _hooks
    ) public returns (PoolKey memory fotKey, uint256 tokenId) {
        vm.startPrank(_account);
        tokenId = lpm.nextTokenId();
        // Initialize a pool with these two tokens
        fotKey = initPoolUnsorted(token0, token1, _hooks, 3000, SQRT_PRICE_1_1);

        uint256 fotBalanceBefore = token0.balanceOf(address(alice));
        console.log(
            "token1 balance efore: %d",
            token1.balanceOf(address(alice))
        );
        console.log("FOT balance before: %d", fotBalanceBefore);

        uint256 amountAfterTransfer = 990e18;
        uint256 amountToSendFot = 1000e18;

        (uint256 amount0, uint256 amount1) = fotKey.currency0 == token0
            ? (amountToSendFot, amountAfterTransfer)
            : (amountAfterTransfer, amountToSendFot);

        // Calculcate the expected liquidity from the amounts after the transfer. They are the same for both currencies.
        uint256 expectedLiquidity = LiquidityAmounts.getLiquidityForAmounts(
            SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(LIQUIDITY_PARAMS.tickLower),
            TickMath.getSqrtPriceAtTick(LIQUIDITY_PARAMS.tickUpper),
            amountAfterTransfer,
            amountAfterTransfer
        );

        Plan memory planner = Planner.init();
        planner.add(
            Actions.SETTLE,
            abi.encode(fotKey.currency0, amount0, true)
        );
        planner.add(
            Actions.SETTLE,
            abi.encode(fotKey.currency1, amount1, true)
        );
        planner.add(
            Actions.MINT_POSITION_FROM_DELTAS,
            abi.encode(
                fotKey,
                LIQUIDITY_PARAMS.tickLower,
                LIQUIDITY_PARAMS.tickUpper,
                MAX_SLIPPAGE_INCREASE,
                MAX_SLIPPAGE_INCREASE,
                _account,
                ZERO_BYTES
            )
        );
        planner.finalizeModifyLiquidityWithClose(fotKey);

        bytes memory plan = planner.encode();

        lpm.modifyLiquidities(plan, _deadline);

        uint256 fotBalanceAfter = token0.balanceOf(address(alice));
        console.log("FOT balance after: %d", fotBalanceAfter);
        console.log(
            "token1 balance after: %d",
            token1.balanceOf(address(alice))
        );

        assertEq(lpm.ownerOf(tokenId), address(alice));
        assertEq(lpm.getPositionLiquidity(tokenId), expectedLiquidity);
        assertEq(fotBalanceBefore - fotBalanceAfter, 990e18);
        uint128 initialLiquidity = lpm.getPositionLiquidity(tokenId);

        planner = Planner.init();
        uint128 newLiquidity = LiquidityAmounts.getLiquidityForAmounts(
            SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(LIQUIDITY_PARAMS.tickLower),
            TickMath.getSqrtPriceAtTick(LIQUIDITY_PARAMS.tickUpper),
            10e18,
            10e18
        );
        planner.add(
            Actions.INCREASE_LIQUIDITY,
            abi.encode(tokenId, newLiquidity, 10e18, 10e18, ZERO_BYTES)
        );
        planner.finalizeModifyLiquidityWithClose(fotKey);

        bytes memory actions = planner.encode();

        lpm.modifyLiquidities(actions, _deadline);

        assertEq(
            lpm.getPositionLiquidity(tokenId),
            initialLiquidity + newLiquidity
        );

        console.log("Liquidity: %d", lpm.getPositionLiquidity(tokenId));

        planner = Planner.init();
        uint128 removedLiquidity = LiquidityAmounts.getLiquidityForAmounts(
            SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(LIQUIDITY_PARAMS.tickLower),
            TickMath.getSqrtPriceAtTick(LIQUIDITY_PARAMS.tickUpper),
            5e18,
            5e18
        );
        planner.add(
            Actions.DECREASE_LIQUIDITY,
            abi.encode(tokenId, removedLiquidity, 0 wei, 0 wei, ZERO_BYTES)
        );
        planner.finalizeModifyLiquidityWithClose(fotKey);

        actions = planner.encode();

        lpm.modifyLiquidities(actions, _deadline);

        assertEq(
            lpm.getPositionLiquidity(tokenId),
            (initialLiquidity + newLiquidity) - removedLiquidity
        );
        vm.stopPrank();
    }
}
