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
import "forge-std/console.sol";

contract DeployPoolPartyDynamicShieldHook is Script, StdAssertions {
    using Planner for Plan;
    using LPFeeLibrary for uint24;

    struct MintData {
        uint256 balance0Before;
        uint256 balance1Before;
        bytes[] params;
    }

    uint256 constant STARTING_USER_BALANCE = 100_000_000_000 ether;

    uint128 public constant MAX_SLIPPAGE_INCREASE = type(uint128).max;
    uint256 public _deadline = block.timestamp + 1;

    PoolManager poolManager;
    PoolSwapTest swapRouter =
        PoolSwapTest(0xe49d2815C231826caB58017e214Bed19fE1c2dD4);
    PoolModifyLiquidityTest modifyLiquidityRouter;
    PositionManager lpm;
    IAllowanceTransfer permit2 =
        IAllowanceTransfer(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    IFeeManager feeManager = IFeeManager(address(0x001));
    IDynamicShieldAVS dynamicShieldAVS = IDynamicShieldAVS(address(0x002));
    IWETH9 public _WETH9 = IWETH9(address(new WETH()));

    Currency currency0;
    Currency currency1;
    Currency stableCurrency;
    MockERC20 USDC;

    PoolKey key;
    PoolPartyDynamicShieldHook shieldHook;

    uint256 privateKey;
    address signerAddr;
    uint256 tokenId;

    function setUp() public virtual {
        privateKey = vm.envUint("PRIVATE_KEY");
        signerAddr = vm.addr(privateKey);
        vm.startBroadcast(signerAddr);
        poolManager = new PoolManager(signerAddr);
        modifyLiquidityRouter = new PoolModifyLiquidityTest(
            poolManager,
            signerAddr
        );
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

        console.log("poolManager:", address(poolManager));
        console.log("modifyLiquidityRouter:", address(modifyLiquidityRouter));
        console.log("PositionManager:", address(lpm));

        console.log("currency0:", address(Currency.unwrap(currency0)));
        console.log("currency1:", address(Currency.unwrap(currency1)));

        seedBalance(signerAddr);

        USDC = new MockERC20("USDC", "USDC", 6);
        console.log("Deployed MockERC20 stableCurrency at", address(USDC));
        stableCurrency = Currency.wrap(address(USDC));
        USDC.mint(signerAddr, STARTING_USER_BALANCE);

        // //Approve tokens
        approvePosmCurrency(currency0);
        approvePosmCurrency(currency1);

        // //Approve stableCurrency
        approvePosmCurrency(stableCurrency);

        seedBalance(signerAddr);
        vm.stopBroadcast();
    }

    function run() public virtual {
        vm.startBroadcast(signerAddr);

        // //Initialize Pool for stableCurrency
        (, PoolKey memory token1USDCKey) = _initPoolsForStableCurrency();

        uint256 amountAfterTransfer = 990e18;
        uint256 amountToSend = 1000e18;

        (uint256 amount0, uint256 amount1) = token1USDCKey.currency0 ==
            currency0
            ? (amountToSend, amountAfterTransfer)
            : (amountAfterTransfer, amountToSend);

        int24 tickLower = -120;
        int24 tickUpper = 120;

        Plan memory planner = Planner.init();
        planner.add(
            Actions.SETTLE,
            abi.encode(token1USDCKey.currency0, amount0, true)
        );
        planner.add(
            Actions.SETTLE,
            abi.encode(token1USDCKey.currency1, amount1, true)
        );
        planner.add(
            Actions.MINT_POSITION_FROM_DELTAS,
            abi.encode(
                token1USDCKey,
                tickLower,
                tickUpper,
                // expectedLiquidity,
                MAX_SLIPPAGE_INCREASE,
                MAX_SLIPPAGE_INCREASE,
                signerAddr,
                Constants.ZERO_BYTES
            )
        );
        // planner.finalizeModifyLiquidityWithSettlePair(token1USDCKey);
        planner.finalizeModifyLiquidityWithClose(token1USDCKey);

        bytes memory plan = planner.encode();
        lpm.modifyLiquidities(plan, _deadline);

        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG |
                Hooks.BEFORE_SWAP_FLAG |
                Hooks.AFTER_SWAP_FLAG
        );

        uint24 _feeInit = 500; // 0.05%
        uint24 _feeMax = 10000; // 1%

        // Find an address + salt using HookMiner that meets our flags criteria
        address CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
        (address hookAddress, bytes32 salt) = HookMiner.find(
            CREATE2_DEPLOYER,
            flags,
            type(PoolPartyDynamicShieldHook).creationCode,
            abi.encode(
                poolManager,
                lpm,
                permit2,
                feeManager,
                stableCurrency,
                _feeInit,
                _feeMax,
                signerAddr
            )
        );

        //Deploy hook
        shieldHook = new PoolPartyDynamicShieldHook{salt: salt}(
            poolManager,
            lpm,
            permit2,
            feeManager,
            stableCurrency,
            _feeInit,
            _feeMax,
            signerAddr
        );
        shieldHook.setAVS(address(dynamicShieldAVS));

        console.log("hookAddress:", address(shieldHook));
        console.log("create2Address:", hookAddress);

        // Ensure it got deployed to our pre-computed address
        require(address(shieldHook) == hookAddress, "hook address mismatch");

        console.log(
            "Deployed PoolPartyDynamicShieldHook at",
            address(shieldHook)
        );

        // //Initialize a pool with these two tokens
        (key, tokenId) = _mintPositionAndIncreaseDecreaseLiquidity(
            signerAddr,
            shieldHook
        );
        console.log("tokenId:", tokenId);
        uint128 initialLiquidity = lpm.getPositionLiquidity(tokenId);
        console.log("Initial liquidity:", initialLiquidity);
        vm.stopBroadcast();
    }

    function _initPoolsForStableCurrency()
        internal
        returns (PoolKey memory token0USDCKey, PoolKey memory token1USDCKey)
    {
        // Load configuration from environment or hardcode for testing
        uint256 usdcAmount = 2000000e6;
        uint24 fee = 3000;

        // Mint USDC
        USDC.mint(msg.sender, usdcAmount);

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
                liquidityDelta: 1000e6,
                salt: bytes32(0)
            }),
            abi.encode(address(signerAddr))
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
            abi.encode(address(signerAddr))
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

    function _mintPositionAndIncreaseDecreaseLiquidity(
        address _account,
        IHooks _hooks
    ) internal returns (PoolKey memory poolKey, uint256 _tokenId) {
        _tokenId = lpm.nextTokenId();

        // Initialize a pool with these two tokens
        poolKey = _initPool(
            currency0,
            currency1,
            _hooks,
            LPFeeLibrary.DYNAMIC_FEE_FLAG,
            Constants.SQRT_PRICE_1_1
        );

        int24 tickLower = -120;
        int24 tickUpper = 120;

        // uint256 balanceBefore = currency0.balanceOf(address(_account));

        // uint256 amountAfterMint = 990e18;

        // // Calculcate the expected liquidity from the amounts after the transfer. They are the same for both currencies.
        // uint256 expectedLiquidity = LiquidityAmounts.getLiquidityForAmounts(
        //     Constants.SQRT_PRICE_1_1,
        //     TickMath.getSqrtPriceAtTick(tickLower),
        //     TickMath.getSqrtPriceAtTick(tickUpper),
        //     amountAfterMint,
        //     amountAfterMint
        // );

        // MintData memory mintData = MintData({
        //     balance0Before: currency0.balanceOf(_account),
        //     balance1Before: currency1.balanceOf(_account),
        //     params: new bytes[](2)
        // });
        // mintData.params[0] = abi.encode(
        //     poolKey,
        //     tickLower,
        //     tickUpper,
        //     expectedLiquidity,
        //     MAX_SLIPPAGE_INCREASE,
        //     MAX_SLIPPAGE_INCREASE,
        //     _account,
        //     Constants.ZERO_BYTES
        // );
        // mintData.params[1] = abi.encode(currency0, currency1);

        // lpm.modifyLiquidities(
        //     abi.encode(
        //         abi.encodePacked(
        //             uint8(Actions.MINT_POSITION),
        //             uint8(Actions.SETTLE_PAIR)
        //         ),
        //         mintData.params
        //     ),
        //     _deadline
        // );
        uint256 balanceBefore = currency0.balanceOf(_account);

        uint256 amountAfterTransfer = 990e18;
        uint256 amountToSend = 1000e18;

        (uint256 amount0, uint256 amount1) = poolKey.currency0 == currency0
            ? (amountToSend, amountAfterTransfer)
            : (amountAfterTransfer, amountToSend);

        // Calculcate the expected liquidity from the amounts after the transfer. They are the same for both currencies.
        uint256 expectedLiquidity = LiquidityAmounts.getLiquidityForAmounts(
            Constants.SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            amount0,
            amount1
        );

        Plan memory planner = Planner.init();
        // planner.add(
        //     Actions.SETTLE,
        //     abi.encode(poolKey.currency0, amount0, true)
        // );
        // planner.add(
        //     Actions.SETTLE,
        //     abi.encode(poolKey.currency1, amount1, true)
        // );
        planner.add(
            Actions.MINT_POSITION,
            abi.encode(
                poolKey,
                tickLower,
                tickUpper,
                expectedLiquidity,
                MAX_SLIPPAGE_INCREASE,
                MAX_SLIPPAGE_INCREASE,
                _account,
                Constants.ZERO_BYTES
            )
        );
        planner.finalizeModifyLiquidityWithSettlePair(poolKey);
        // planner.finalizeModifyLiquidityWithClose(poolKey);

        bytes memory plan = planner.encode();
        lpm.modifyLiquidities(plan, _deadline);

        uint256 balanceAfter = currency0.balanceOf(address(signerAddr));

        console.log("lpm.ownerOf(tokenId)", lpm.ownerOf(_tokenId));
        assertEq(lpm.ownerOf(_tokenId), address(signerAddr));
        assertEq(lpm.getPositionLiquidity(_tokenId), expectedLiquidity);
        assertEq(balanceBefore - balanceAfter, 990e18);
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
            Constants.ZERO_BYTES
        );
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
}
