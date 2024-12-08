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
import {IPoolModifyLiquidity} from "../src/interfaces/IPoolModifyLiquidity.sol";

import {DynamicShieldAVS, IDynamicShieldAVS} from "./mock/DynamicShieldAVS.sol";
import {FeeManager, IFeeManager} from "./mock/FeeManager.sol";

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
    IDynamicShieldAVS s_dynamicShieldAVS;
    IFeeManager s_feeManager;

    address alice;
    uint256 alicePK;
    uint256 tokenId;

    function setUp() public {
        (alice, alicePK) = makeAddrAndKey("ALICE");
        s_dynamicShieldAVS = new DynamicShieldAVS();
        s_feeManager = new FeeManager();

        // Deploy v4 core contracts
        deployFreshManagerAndRouters();

        // Deploy two test tokens
        (token0, token1) = deployMintAndApprove2Currencies();

        USDC = new MockERC20("USDC", "USDC", 6);
        stableCoin = Currency.wrap(address(USDC));
        console.log("============>>>> USDC", address(USDC));
        IERC20(Currency.unwrap(stableCoin)).approve(address(manager), type(uint256).max);
        IERC20(Currency.unwrap(stableCoin)).approve(address(modifyLiquidityRouter), type(uint256).max);

        // Requires currency0 and currency1 to be set in base Deployers contract.
        deployAndApprovePosm(manager);

        approvePosmCurrency(stableCoin);

        _initPoolsForStableCoin();

        seedBalance(alice);
        approvePosmFor(alice);

        IERC20(Currency.unwrap(currency0)).approve(address(manager), type(uint256).max);
        IERC20(Currency.unwrap(currency1)).approve(address(manager), type(uint256).max);
        IERC20(Currency.unwrap(currency0)).approve(address(modifyLiquidityRouter), type(uint256).max);
        IERC20(Currency.unwrap(currency1)).approve(address(modifyLiquidityRouter), type(uint256).max);

        // Deploy our hook
        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG |
                Hooks.BEFORE_SWAP_FLAG |
                Hooks.AFTER_SWAP_FLAG
        );
        address hookAddress = address(flags);
        uint24 _feeInit = 500; // 0.05%
        uint24 _feeMax = 10000; // 1%

        deployCodeTo(
            "PoolPartyDynamicShieldHook.sol",
            abi.encode(
                manager,
                s_feeManager,
                stableCoin,
                _feeInit,
                _feeMax,
                address(alice)
            ),
            hookAddress
        );
        s_shieldHook = PoolPartyDynamicShieldHook(hookAddress);

        // Initialize a pool with these two tokens

        key = initPoolUnsorted(
            token0,
            token1,
            s_shieldHook,
            LPFeeLibrary.DYNAMIC_FEE_FLAG,
            SQRT_PRICE_1_1
        );

        // Add initial liquidity to the pool
        _addLiquidityByLiquidityRouter(key, bytes32(0), -60, 60, 10 ether);

        vm.startPrank(alice);
        IERC20(Currency.unwrap(currency0)).approve(address(manager), type(uint256).max);
        IERC20(Currency.unwrap(currency1)).approve(address(manager), type(uint256).max);
        IERC20(Currency.unwrap(currency0)).approve(address(modifyLiquidityRouter), type(uint256).max);
        IERC20(Currency.unwrap(currency1)).approve(address(modifyLiquidityRouter), type(uint256).max);
        s_shieldHook.registerAVS(address(s_dynamicShieldAVS));
        vm.stopPrank();
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
                liquidityDelta: 2000e6,
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
            // if (i % 2 == 0) {
            //     params.zeroForOne = false;
            // } else {
            //     params.zeroForOne = true;
            // }
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

    function mapToAddLiquidityParams(
        uint160 sqrtPriceX96,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0,
        uint256 amount1
    ) public pure returns (IPoolManager.ModifyLiquidityParams memory params) {
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            amount0,
            amount1
        );

        params = IPoolManager.ModifyLiquidityParams({
            tickLower: tickLower,
            tickUpper: tickUpper,
            liquidityDelta: int256(uint256(liquidity)),
            salt: bytes32(0)
        });
    }

    function mapToRemoveLiquidityParams(
        int24 tickLower,
        int24 tickUpper,
        int256 liquidity
    ) public pure returns (IPoolManager.ModifyLiquidityParams memory params) {
        params = IPoolManager.ModifyLiquidityParams({
            tickLower: tickLower,
            tickUpper: tickUpper,
            liquidityDelta: liquidity,
            salt: bytes32(0)
        });
    }
}
