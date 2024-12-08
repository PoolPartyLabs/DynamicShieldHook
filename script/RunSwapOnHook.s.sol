// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {PoolModifyLiquidityTest} from "../test/PoolModifyLiquidityTest.sol";
import {PoolDonateTest} from "v4-core/src/test/PoolDonateTest.sol";
import {PoolTakeTest} from "v4-core/src/test/PoolTakeTest.sol";
import {PoolClaimsTest} from "v4-core/src/test/PoolClaimsTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {PositionManager} from "v4-periphery/src/PositionManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {PoolPartyDynamicShieldHook, IFeeManager, IDynamicShieldAVS} from "../src/PoolPartyDynamicShieldHook.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {Constants} from "v4-core/test/utils/Constants.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {DeployPermit2} from "permit2/test/utils/DeployPermit2.sol";
import {LPFeeLibrary} from "v4-core/src/libraries/LPFeeLibrary.sol";
import {ActionConstants} from "v4-periphery/src/libraries/ActionConstants.sol";
import {Actions} from "v4-periphery/src/libraries/Actions.sol";
import {Planner, Plan} from "../src/library/external/Planner.sol";
import {HookMiner} from "../utils/HookMiner.sol";
import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";
import {StdAssertions} from "forge-std/StdAssertions.sol";
import {SortTokens} from "v4-core/test/utils/SortTokens.sol";
import {PositionDescriptor} from "v4-periphery/src/PositionDescriptor.sol";
import {IWETH9} from "v4-periphery/src/interfaces/external/IWETH9.sol";
import {WETH} from "solmate/src/tokens/WETH.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {DynamicShieldHookDeploymentLib} from "../src/library/DynamicShieldHookDeploymentLib.sol";
import {DynamicShieldAVS} from "../test/mock/DynamicShieldAVS.sol";
import {FeeManager} from "../test/mock/FeeManager.sol";
import "forge-std/console.sol";

contract RunSwapOnHook is Script, StdAssertions {
    using Planner for Plan;
    using LPFeeLibrary for uint24;
    using PoolIdLibrary for PoolKey;

    // Helpful test constants
    bytes constant ZERO_BYTES = Constants.ZERO_BYTES;
    uint160 constant SQRT_PRICE_1_1 = Constants.SQRT_PRICE_1_1;
    uint160 constant SQRT_PRICE_1_2 = Constants.SQRT_PRICE_1_2;

    IPoolManager.SwapParams public SWAP_PARAMS =
        IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: -100,
            sqrtPriceLimitX96: SQRT_PRICE_1_2
        });


    PoolManager poolManager =
        PoolManager(0x897A8C523018CecC2Ec4A9aBe5cBecb379f86c4a);

    PoolSwapTest swapRouter =
        PoolSwapTest(0x094592E865bC4c1cF4aEF53068c7eb6bffaf33a8);

    PoolModifyLiquidityTest modifyLiquidityRouter =
        PoolModifyLiquidityTest(0x464eb2ee6e3b8B061265DfA7c8AAf59D80390f7E);

    Currency currency0 =
        Currency.wrap(address(0xb6900011Ff85dA0f990bE424Aa88F4dBf2442584));

    Currency currency1 =
        Currency.wrap(address(0xb89D175c8386042fd3dC192caeC6B2ff1a2887D7));

    Currency stableCurrency =
        Currency.wrap(address(0x9a5Ae52Cfb54a589FbF602191358a293C1681173));

    PoolPartyDynamicShieldHook shieldHook =
        PoolPartyDynamicShieldHook(0x35f897B1f85E13001b246ac7fF1BF1aa0a82A0C0);

    DynamicShieldHookDeploymentLib.DeploymentData dynamicShieldHookDeployment;
    IDynamicShieldAVS dynamicShieldAVS;
    IFeeManager feeManager;
    PoolKey key;

    uint256 privateKey;
    address signerAddr;
    uint256 tokenId = 1;

    function setUp() public virtual {
        privateKey = vm.envUint("PRIVATE_KEY");
        signerAddr = vm.addr(privateKey);
    }

    function run() public virtual {
        vm.startBroadcast(signerAddr);
        uint256 numOfKeys = 1;
        PoolKey[] memory pools = new PoolKey[](numOfKeys);
        int256[] memory amounts = new int256[](numOfKeys);

        MockERC20(Currency.unwrap(currency0)).mint(signerAddr, 1000000000e18);
        MockERC20(Currency.unwrap(currency1)).mint(signerAddr, 1000000000e18);
        MockERC20(Currency.unwrap(currency0)).mint(
            address(this),
            1000000000e18
        );
        MockERC20(Currency.unwrap(currency1)).mint(
            address(this),
            1000000000e18
        );
        MockERC20(Currency.unwrap(stableCurrency)).mint(
            signerAddr,
            1000000000e18
        );
        MockERC20(Currency.unwrap(stableCurrency)).mint(
            address(this),
            1000000000e18
        );
        key = _initPool(
            currency0,
            currency1,
            shieldHook,
            LPFeeLibrary.DYNAMIC_FEE_FLAG,
            SQRT_PRICE_1_1
        );
        console.log("PoolId:");
        console.logBytes32(PoolId.unwrap(key.toId()));

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
        console.log("BEFORE SWAP");
        console.log(
            "getPositionLiquidity",
            shieldHook.getPositionLiquidity(tokenId)
        );
        console.log(
            "currency0 balance",
            IERC20(Currency.unwrap(currency0)).balanceOf(
                shieldHook.getVaulManagerAddress()
            )
        );
        console.log(
            "currency1 balance",
            IERC20(Currency.unwrap(currency1)).balanceOf(
                shieldHook.getVaulManagerAddress()
            )
        );
        console.log(
            "stableCurrency balance",
            IERC20(Currency.unwrap(stableCurrency)).balanceOf(
                shieldHook.getVaulManagerAddress()
            )
        );

        for (uint256 i = 0; i < numOfKeys; i++) {
            pools[i] = key;
            if (i % 2 == 0) {
                amounts[i] = 10e18;
            } else {
                amounts[i] = -10e18;
            }
        }
        _swapMulti(pools, amounts);

        console.log("AFTER SWAP");
        console.log(
            "getPositionLiquidity",
            shieldHook.getPositionLiquidity(tokenId)
        );
        console.log(
            "currency0 balance",
            IERC20(Currency.unwrap(currency0)).balanceOf(
                shieldHook.getVaulManagerAddress()
            )
        );
        console.log(
            "currency1 balance",
            IERC20(Currency.unwrap(currency1)).balanceOf(
                shieldHook.getVaulManagerAddress()
            )
        );
        console.log(
            "stableCurrency balance",
            IERC20(Currency.unwrap(stableCurrency)).balanceOf(
                shieldHook.getVaulManagerAddress()
            )
        );
        vm.stopBroadcast();
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

        for (uint256 i = 0; i < poolsLength; i++) {
            // if (i % 2 == 0) {
            //     params.zeroForOne = false;
            // } else {
            //     params.zeroForOne = true;
            // }
            SWAP_PARAMS.amountSpecified = _amounts[i];
            swapRouter.swap(_pools[i], SWAP_PARAMS, testSettings, ZERO_BYTES);
        }
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

    function _initPool(
        Currency currencyA,
        Currency currencyB,
        IHooks hooks,
        uint24 fee,
        uint160 
    ) public       pure
returns (PoolKey memory poolKey) {
        (Currency _currency0, Currency _currency1) = SortTokens.sort(
            MockERC20(Currency.unwrap(currencyA)),
            MockERC20(Currency.unwrap(currencyB))
        );
        poolKey = PoolKey(_currency0, _currency1, fee, int24(60), hooks);
        // poolManager.initialize(poolKey, sqrtPriceX96);
    }
}
