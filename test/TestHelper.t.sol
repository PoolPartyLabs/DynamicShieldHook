// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Foundry libraries
import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {PoolManager} from "v4-core/src/PoolManager.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {LPFeeLibrary} from "v4-core/src/libraries/LPFeeLibrary.sol";

import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";

import {PosmTestSetup} from "v4-periphery/test/shared/PosmTestSetup.sol";
import {BipsLibrary} from "v4-periphery/src/libraries/BipsLibrary.sol";
import {ActionConstants} from "v4-periphery/src/libraries/ActionConstants.sol";
import {Actions} from "v4-periphery/src/libraries/Actions.sol";

// Our contracts
import {Planner, Plan} from "../src/library/external/Planner.sol";
import {PoolPartyDynamicShieldHook} from "../src/PoolPartyDynamicShieldHook.sol";

abstract contract TestHelper is PosmTestSetup {
    // Use the libraries
    using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using Planner for Plan;
    using BipsLibrary for uint256;

    // The two currencies (tokens) from the pool
    Currency token0;
    Currency token1;
    Currency stableCoin;
    MockERC20 USDC;

    PoolPartyDynamicShieldHook s_shieldHook;

    address alice;
    uint256 alicePK;
    uint256 tokenId;

    function setUp() public {
        (alice, alicePK) = makeAddrAndKey("ALICE");

        // Deploy v4 core contracts
        deployFreshManagerAndRouters();

        // Deploy two test tokens
        (token0, token1) = deployMintAndApprove2Currencies();

        USDC = new MockERC20("USDC", "USDC", 6);
        stableCoin = Currency.wrap(address(USDC));
        console.log("============>>>> USDC", address(USDC));

        // Requires currency0 and currency1 to be set in base Deployers contract.
        deployAndApprovePosm(manager);

        approvePosmCurrency(stableCoin);

        _initPoolsForStableCoin();

        seedBalance(alice);
        approvePosmFor(alice);

        // Deploy our hook
        uint160 flags = uint160(Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_SWAP_FLAG);
        address hookAddress = address(flags);
        deployCodeTo(
            "PoolPartyDynamicShieldHook.sol",
            abi.encode(manager, lpm, permit2),
            hookAddress
        );
        s_shieldHook = PoolPartyDynamicShieldHook(hookAddress);

        // Initialize a pool with these two tokens
        (key, tokenId) = _mintPositionAndIncreaseDecreaseLiquidity(
            alice,
            s_shieldHook
        );

        // Add initial liquidity to the pool
        _addLiquidityByLiquidityRouter(key, bytes32(0), -60, 60, 10 ether);
    }

    function _getLiquidity(
        PoolKey memory _key,
        address _owner,
        int24 _tickLower,
        int24 _tickUpper,
        bytes32 _salt
    ) internal view returns (uint128 liquidity) {
        (liquidity, , ) = manager.getPositionInfo(
            _key.toId(),
            _owner,
            _tickLower,
            _tickUpper,
            _salt
        );
    }

    function _initPoolsForStableCoin() internal {
        uint256 usdcAmount = 2000000e6;
        uint24 fee = 3000;

        USDC.mint(address(this), usdcAmount);

        IERC20(address(USDC)).approve(
            address(modifyLiquidityRouter),
            type(uint256).max
        );
        IERC20(Currency.unwrap(token0)).approve(
            address(modifyLiquidityRouter),
            type(uint256).max
        );
        IERC20(Currency.unwrap(token1)).approve(
            address(modifyLiquidityRouter),
            type(uint256).max
        );

        PoolKey memory token0USDCKey = initPoolUnsorted(
            token0,
            stableCoin,
            IHooks(address(0)),
            fee,
            SQRT_PRICE_1_1
        );
        // some liquidity for full range
        modifyLiquidityRouter.modifyLiquidity(
            token0USDCKey,
            IPoolManager.ModifyLiquidityParams({
                tickLower: TickMath.minUsableTick(60),
                tickUpper: TickMath.maxUsableTick(60),
                liquidityDelta: 1000e6,
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );

        PoolKey memory token1USDCKey = initPoolUnsorted(
            stableCoin,
            token1,
            IHooks(address(0)),
            fee,
            SQRT_PRICE_1_1
        );
        // some liquidity for full range
        modifyLiquidityRouter.modifyLiquidity(
            token1USDCKey,
            IPoolManager.ModifyLiquidityParams({
                tickLower: TickMath.minUsableTick(60),
                tickUpper: TickMath.maxUsableTick(60),
                liquidityDelta: 2000e6,
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );
    }

    function _mintPositionAndIncreaseDecreaseLiquidity(
        address _account,
        IHooks _hooks
    ) internal returns (PoolKey memory poolKey, uint256 _tokenId) {
        _tokenId = lpm.nextTokenId();
        // Initialize a pool with these two tokens
        poolKey = initPoolUnsorted(
            token0,
            token1,
            _hooks,
            LPFeeLibrary.DYNAMIC_FEE_FLAG,
            SQRT_PRICE_1_1
        );

        vm.startPrank(_account);
        uint256 balanceBefore = token0.balanceOf(address(alice));

        uint256 amountAfterTransfer = 990e18;
        uint256 amountToSend = 1000e18;

        (uint256 amount0, uint256 amount1) = poolKey.currency0 == token0
            ? (amountToSend, amountAfterTransfer)
            : (amountAfterTransfer, amountToSend);

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
            abi.encode(poolKey.currency0, amount0, true)
        );
        planner.add(
            Actions.SETTLE,
            abi.encode(poolKey.currency1, amount1, true)
        );
        planner.add(
            Actions.MINT_POSITION_FROM_DELTAS,
            abi.encode(
                poolKey,
                LIQUIDITY_PARAMS.tickLower,
                LIQUIDITY_PARAMS.tickUpper,
                MAX_SLIPPAGE_INCREASE,
                MAX_SLIPPAGE_INCREASE,
                _account,
                ZERO_BYTES
            )
        );
        planner.finalizeModifyLiquidityWithClose(poolKey);

        bytes memory plan = planner.encode();
        lpm.modifyLiquidities(plan, _deadline);

        uint256 balanceAfter = token0.balanceOf(address(alice));

        assertEq(lpm.ownerOf(_tokenId), address(alice));
        assertEq(lpm.getPositionLiquidity(_tokenId), expectedLiquidity);
        assertEq(balanceBefore - balanceAfter, 990e18);
        uint128 initialLiquidity = lpm.getPositionLiquidity(_tokenId);

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
            abi.encode(_tokenId, newLiquidity, 10e18, 10e18, ZERO_BYTES)
        );
        planner.finalizeModifyLiquidityWithClose(poolKey);

        bytes memory actions = planner.encode();

        lpm.modifyLiquidities(actions, _deadline);

        assertEq(
            lpm.getPositionLiquidity(_tokenId),
            initialLiquidity + newLiquidity
        );

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
            abi.encode(_tokenId, removedLiquidity, 0 wei, 0 wei, ZERO_BYTES)
        );
        planner.finalizeModifyLiquidityWithClose(poolKey);

        actions = planner.encode();

        lpm.modifyLiquidities(actions, _deadline);

        assertEq(
            lpm.getPositionLiquidity(_tokenId),
            (initialLiquidity + newLiquidity) - removedLiquidity
        );
        vm.stopPrank();
    }

    function _swapMulti(
        PoolKey[] memory _pools,
        int256[] memory _amounts
    ) internal {
        uint256 poolsLength = _pools.length;
        require(poolsLength == _amounts.length, "Invalid input");

        // Set up our swap parameters
        PoolSwapTest.TestSettings memory testSettings = PoolSwapTest
            .TestSettings({takeClaims: false, settleUsingBurn: false});

        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: -100 ether,
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        for (uint256 i = 0; i < poolsLength; i++) {
            params.amountSpecified = _amounts[i];
            swapRouter.swap(_pools[i], params, testSettings, ZERO_BYTES);
        }
    }

    function _addLiquidityByLiquidityRouter(
        PoolKey memory _key,
        bytes32 _salt,
        int24 _tickLower,
        int24 _tickUpper,
        int256 _liquidity
    ) internal {
        modifyLiquidityRouter.modifyLiquidity(
            _key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: _tickLower,
                tickUpper: _tickUpper,
                liquidityDelta: _liquidity,
                salt: _salt
            }),
            ZERO_BYTES
        );
    }
}
