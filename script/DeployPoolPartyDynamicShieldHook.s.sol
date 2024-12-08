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
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {PoolPartyDynamicShieldHook, IFeeManager, IDynamicShieldAVS} from "../src/PoolPartyDynamicShieldHook.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {Constants} from "v4-core/test/utils/Constants.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {DeployPermit2} from "permit2/test/utils/DeployPermit2.sol";
import {LPFeeLibrary} from "v4-core/src/libraries/LPFeeLibrary.sol";
import {ActionConstants} from "v4-periphery/src/libraries/ActionConstants.sol";
import {Actions} from "v4-periphery/src/libraries/Actions.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {Planner, Plan} from "../src/library/external/Planner.sol";
import {HookMiner} from "../utils/HookMiner.sol";
import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";
import {StdAssertions} from "forge-std/StdAssertions.sol";
import {SortTokens} from "v4-core/test/utils/SortTokens.sol";
import {PositionDescriptor} from "v4-periphery/src/PositionDescriptor.sol";
import {IWETH9} from "v4-periphery/src/interfaces/external/IWETH9.sol";
import {WETH} from "solmate/src/tokens/WETH.sol";
import {DynamicShieldHookDeploymentLib} from "../src/library/DynamicShieldHookDeploymentLib.sol";
import {DynamicShieldAVSDeploymentLib} from "../src/eigenlayer/library/DynamicShieldAVSDeploymentLib.sol";
import {DynamicShieldAVS} from "../test/mock/DynamicShieldAVS.sol";
import {FeeManager} from "../test/mock/FeeManager.sol";
import "forge-std/console.sol";

contract DeployPoolPartyDynamicShieldHook is Script, StdAssertions {
    using Planner for Plan;
    using LPFeeLibrary for uint24;
    using PoolIdLibrary for PoolKey;

    // Helpful test constants
    bytes constant ZERO_BYTES = Constants.ZERO_BYTES;
    uint160 constant SQRT_PRICE_1_1 = Constants.SQRT_PRICE_1_1;
    uint160 constant SQRT_PRICE_1_2 = Constants.SQRT_PRICE_1_2;
    uint160 constant SQRT_PRICE_2_1 = Constants.SQRT_PRICE_2_1;
    uint160 constant SQRT_PRICE_1_4 = Constants.SQRT_PRICE_1_4;
    uint160 constant SQRT_PRICE_4_1 = Constants.SQRT_PRICE_4_1;

    uint160 public constant MIN_PRICE_LIMIT = TickMath.MIN_SQRT_PRICE + 1;
    uint160 public constant MAX_PRICE_LIMIT = TickMath.MAX_SQRT_PRICE - 1;

    IPoolManager.ModifyLiquidityParams public LIQUIDITY_PARAMS =
        IPoolManager.ModifyLiquidityParams({
            tickLower: -120,
            tickUpper: 120,
            liquidityDelta: 1e18,
            salt: 0
        });
    IPoolManager.ModifyLiquidityParams public REMOVE_LIQUIDITY_PARAMS =
        IPoolManager.ModifyLiquidityParams({
            tickLower: -120,
            tickUpper: 120,
            liquidityDelta: -1e18,
            salt: 0
        });
    uint256 constant STARTING_USER_BALANCE = 100_000_000_000 ether;

    uint128 public constant MAX_SLIPPAGE_INCREASE = type(uint128).max;
    uint256 public _deadline = block.timestamp + 1;

    PoolManager poolManager;
    PoolSwapTest swapRouter;
    PoolModifyLiquidityTest modifyLiquidityRouter;
    PositionManager lpm;
    IAllowanceTransfer permit2 =
        IAllowanceTransfer(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    IWETH9 public _WETH9 = IWETH9(address(new WETH()));

    Currency currency0;
    Currency currency1;
    Currency stableCurrency;
    MockERC20 USDC;

    PoolKey key;
    PoolPartyDynamicShieldHook shieldHook;

    DynamicShieldHookDeploymentLib.DeploymentData dynamicShieldHookDeployment;
    DynamicShieldAVSDeploymentLib.DeploymentData dynamicShieldAVSDeployment;
    IDynamicShieldAVS dynamicShieldAVS;
    IFeeManager feeManager;

    uint256 privateKey;
    address signerAddr;
    uint256 tokenId;

    function setUp() public virtual {
        privateKey = vm.envUint("PRIVATE_KEY");
        signerAddr = vm.addr(privateKey);
        vm.startBroadcast(signerAddr);
        poolManager = new PoolManager(signerAddr);

        swapRouter = new PoolSwapTest(poolManager);

        // dynamicShieldAVS = new DynamicShieldAVS();
        feeManager = new FeeManager();

        modifyLiquidityRouter = new PoolModifyLiquidityTest(poolManager);
        PositionDescriptor positionDescriptor = new PositionDescriptor(
            poolManager,
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            "ETH"
        );
        lpm = new PositionManager(
            poolManager,
            permit2,
            100_000,
            positionDescriptor,
            _WETH9
        );

        deployMintAndApprove2Currencies();

        console.log("\n poolManager:", address(poolManager));
        console.log("\n swapRouter:", address(swapRouter));
        console.log(
            "\n modifyLiquidityRouter:",
            address(modifyLiquidityRouter)
        );
        // console.log("PositionManager:", address(lpm));

        console.log("\n currency0:", address(Currency.unwrap(currency0)));
        console.log("\n currency1:", address(Currency.unwrap(currency1)));

        seedBalance(signerAddr);

        USDC = new MockERC20("USDC", "USDC", 6);
        console.log("\n stableCurrency:", address(USDC));
        stableCurrency = Currency.wrap(address(USDC));
        USDC.mint(signerAddr, STARTING_USER_BALANCE);
        USDC.mint(signerAddr, STARTING_USER_BALANCE);

        // //Approve tokens
        approvePosmCurrency(currency0);
        approvePosmCurrency(currency1);

        // //Approve stableCurrency
        approvePosmCurrency(stableCurrency);

        seedBalance(signerAddr);

        uint24 _feeInit = 500; // 0.05%
        uint24 _feeMax = 10000; // 1%

        dynamicShieldHookDeployment = DynamicShieldHookDeploymentLib
            .deployContracts(
                poolManager,
                feeManager,
                stableCurrency,
                _feeInit,
                _feeMax,
                signerAddr
            );

        dynamicShieldAVSDeployment = DynamicShieldAVSDeploymentLib
            .readDeploymentJson(block.chainid);

        console.log(
            "\n PoolPartyDynamicShieldHook: ",
            address(dynamicShieldHookDeployment.dynamicShield)
        );

        console.log(
            "\n DynamicShieldAVS: ",
            address(dynamicShieldAVSDeployment.dynamicShieldAVS)
        );
        console.log("\n \n");

        shieldHook = PoolPartyDynamicShieldHook(
            address(dynamicShieldHookDeployment.dynamicShield)
        );

        vm.stopBroadcast();

        DynamicShieldHookDeploymentLib.writeDeploymentJson(
            dynamicShieldHookDeployment
        );

        vm.startBroadcast(signerAddr);
        //Initialize a pool with stableCurrency and token0/token1
        _initPoolsForStableCurrency();
        vm.stopBroadcast();
    }

    function run() public virtual {
        vm.startBroadcast(signerAddr);

        //Initialize a pool with these two tokens
        (key, tokenId) = _mintPositionAndAddLiquidity(signerAddr, shieldHook);
        console.log("tokenId:", tokenId);
        console.log("PoolId:");
        console.logBytes32(PoolId.unwrap(key.toId()));
        vm.stopBroadcast();
    }

    function _initPoolsForStableCurrency()
        internal
        returns (PoolKey memory token0USDCKey, PoolKey memory token1USDCKey)
    {
        // Load configuration from environment or hardcode for testing
        uint256 usdcAmount = 2000000e19;
        uint24 fee = 3000;

        // Mint USDC
        USDC.mint(address(this), usdcAmount);

        // Approve tokens for liquidity router
        IERC20(address(USDC)).approve(
            address(modifyLiquidityRouter),
            type(uint256).max
        );
        IERC20(Currency.unwrap(currency0)).approve(
            address(modifyLiquidityRouter),
            type(uint256).max
        );
        IERC20(Currency.unwrap(currency1)).approve(
            address(modifyLiquidityRouter),
            type(uint256).max
        );

        // Initialize token0/USDC pool and add liquidity
        token0USDCKey = _initPool(
            currency0,
            stableCurrency,
            IHooks(address(0)),
            fee,
            Constants.SQRT_PRICE_1_1
        );

        modifyLiquidityRouter.modifyLiquidity(
            token0USDCKey,
            IPoolManager.ModifyLiquidityParams({
                tickLower: TickMath.minUsableTick(60),
                tickUpper: TickMath.maxUsableTick(60),
                liquidityDelta: 2000e6,
                salt: bytes32(0)
            }),
            Constants.ZERO_BYTES
        );

        // Initialize token1/USDC pool and add liquidity
        token1USDCKey = _initPool(
            stableCurrency,
            currency1,
            IHooks(address(0)),
            fee,
            Constants.SQRT_PRICE_1_1
        );
        modifyLiquidityRouter.modifyLiquidity(
            token1USDCKey,
            IPoolManager.ModifyLiquidityParams({
                tickLower: TickMath.minUsableTick(60),
                tickUpper: TickMath.maxUsableTick(60),
                liquidityDelta: 2000e6,
                salt: bytes32(0)
            }),
            Constants.ZERO_BYTES
        );
    }

    function approvePosmCurrency(Currency currency) internal {
        IERC20(Currency.unwrap(currency)).approve(
            address(permit2),
            type(uint256).max
        );
        IERC20(Currency.unwrap(currency)).approve(
            address(lpm),
            type(uint256).max
        );
        IERC20(Currency.unwrap(currency)).approve(
            address(poolManager),
            type(uint256).max
        );
        permit2.approve(
            Currency.unwrap(currency),
            address(lpm),
            type(uint160).max,
            type(uint48).max
        );
        permit2.approve(
            Currency.unwrap(currency),
            address(poolManager),
            type(uint160).max,
            type(uint48).max
        );
    }

    function _mintPositionAndAddLiquidity(
        address _account,
        IHooks _hooks
    ) internal returns (PoolKey memory poolKey, uint256 _tokenId) {
        // Initialize a pool with these two tokens
        poolKey = _initPool(
            currency0,
            currency1,
            _hooks,
            LPFeeLibrary.DYNAMIC_FEE_FLAG,
            Constants.SQRT_PRICE_1_1
        );

        _tokenId = _initShield(poolKey, _account);
    }

    function _initPool(
        Currency currencyA,
        Currency currencyB,
        IHooks hooks,
        uint24 fee,
        uint160 sqrtPriceX96
    ) public returns (PoolKey memory poolKey) {
        (Currency _currency0, Currency _currency1) = SortTokens.sort(
            MockERC20(Currency.unwrap(currencyA)),
            MockERC20(Currency.unwrap(currencyB))
        );
        poolKey = PoolKey(_currency0, _currency1, fee, int24(60), hooks);
        poolManager.initialize(poolKey, sqrtPriceX96);
    }

    function deployMintAndApprove2Currencies()
        internal
        returns (Currency, Currency)
    {
        Currency _currencyA = deployMintAndApproveCurrency();
        Currency _currencyB = deployMintAndApproveCurrency();

        (currency0, currency1) = SortTokens.sort(
            MockERC20(Currency.unwrap(_currencyA)),
            MockERC20(Currency.unwrap(_currencyB))
        );
        return (currency0, currency1);
    }

    function deployMintAndApproveCurrency()
        internal
        returns (Currency currency)
    {
        MockERC20 token = deployTokens(1, 2 ** 255)[0];

        address[4] memory toApprove = [
            address(swapRouter),
            address(modifyLiquidityRouter),
            address(poolManager),
            address(lpm)
        ];

        for (uint256 i = 0; i < toApprove.length; i++) {
            token.approve(toApprove[i], Constants.MAX_UINT256);
        }

        return Currency.wrap(address(token));
    }

    function deployTokens(
        uint8 count,
        uint256 totalSupply
    ) internal returns (MockERC20[] memory tokens) {
        tokens = new MockERC20[](count);
        for (uint8 i = 0; i < count; i++) {
            tokens[i] = new MockERC20("TEST", "TEST", 18);
            tokens[i].mint(address(this), totalSupply);
        }
    }

    function seedBalance(address to) internal {
        MockERC20(Currency.unwrap(currency0)).mint(to, STARTING_USER_BALANCE);
        MockERC20(Currency.unwrap(currency1)).mint(to, STARTING_USER_BALANCE);
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

    function _initShield(
        PoolKey memory _poolKey,
        address _account
    ) internal returns (uint256 _tokenId) {
        IERC20(address(USDC)).approve(address(shieldHook), type(uint256).max);
        IERC20(Currency.unwrap(currency0)).approve(
            address(shieldHook),
            type(uint256).max
        );
        IERC20(Currency.unwrap(currency1)).approve(
            address(shieldHook),
            type(uint256).max
        );

        _tokenId = shieldHook.initializeShield(
            _poolKey,
            mapToAddLiquidityParams(
                SQRT_PRICE_1_1,
                LIQUIDITY_PARAMS.tickLower,
                LIQUIDITY_PARAMS.tickUpper,
                100e18,
                100e18
            ),
            100e18,
            100e18
        );

        console.log("minted _tokenId: ", _tokenId);
        console.log(
            "position Liquidity: ",
            shieldHook.getPositionLiquidity(_tokenId)
        );
        assertEq(shieldHook.ownerOf(_tokenId), _account);
    }
}
