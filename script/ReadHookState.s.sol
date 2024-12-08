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

contract ReadHookState is Script, StdAssertions {
    using Planner for Plan;
    using LPFeeLibrary for uint24;
    using PoolIdLibrary for PoolKey;

    bytes constant ZERO_BYTES = Constants.ZERO_BYTES;
    uint160 constant SQRT_PRICE_1_1 = Constants.SQRT_PRICE_1_1;
    uint160 constant SQRT_PRICE_1_2 = Constants.SQRT_PRICE_1_2;

    PoolManager poolManager =
        PoolManager(0x34e7F7a5Cb17511277825B74E3E248b8298C7C2b);

    PoolSwapTest swapRouter =
        PoolSwapTest(0xF40eBa61b3Fae5056b5E8452B77E52bEf05A5D34);

    PoolModifyLiquidityTest modifyLiquidityRouter =
        PoolModifyLiquidityTest(0x671A2Aa5315c7bc1C4c0bC50A5c0B3feb15d32Dd);

    Currency currency0 =
        Currency.wrap(address(0x3fa9f0F3bBD69df2A3e0E685B5A5D272AdaF13ED));

    Currency currency1 =
        Currency.wrap(address(0xE8f3A618E3C3e0d1aFD60df04Fa6f632CB8617b4));

    Currency stableCurrency =
        Currency.wrap(address(0xd8182E11b110F8e5A35f069CA9DA1F28B51eE60c));

    PoolPartyDynamicShieldHook shieldHook =
        PoolPartyDynamicShieldHook(0xf4aBa09ac167da988f4C386136d61120cbe7A0C0);

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
        key = _initPool(
            currency0,
            currency1,
            shieldHook,
            LPFeeLibrary.DYNAMIC_FEE_FLAG,
            SQRT_PRICE_1_1
        );
        console.log("PoolId:");
        console.logBytes32(PoolId.unwrap(key.toId()));

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

    function _initPool(
        Currency currencyA,
        Currency currencyB,
        IHooks hooks,
        uint24 fee,
        uint160
    ) public pure returns (PoolKey memory poolKey) {
        (Currency _currency0, Currency _currency1) = SortTokens.sort(
            MockERC20(Currency.unwrap(currencyA)),
            MockERC20(Currency.unwrap(currencyB))
        );
        poolKey = PoolKey(_currency0, _currency1, fee, int24(60), hooks);
        // poolManager.initialize(poolKey, sqrtPriceX96);
    }
}
