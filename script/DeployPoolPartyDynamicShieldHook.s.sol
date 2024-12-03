// NOTE: This is based on V4PreDeployed.s.sol
// You can make changes to base on V4Deployer.s.sol to deploy everything fresh as well

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {PoolModifyLiquidityTest} from "v4-core/src/test/PoolModifyLiquidityTest.sol";
import {PoolDonateTest} from "v4-core/src/test/PoolDonateTest.sol";
import {PoolTakeTest} from "v4-core/src/test/PoolTakeTest.sol";
import {PoolClaimsTest} from "v4-core/src/test/PoolClaimsTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {PoolPartyDynamicShieldHook} from "../src/PoolPartyDynamicShieldHook.sol";
import {PosmTestSetup} from "v4-periphery/test/shared/PosmTestSetup.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {Constants} from "v4-core/test/utils/Constants.sol";
import "forge-std/console.sol";

contract DeployPoolPartyDynamicShieldHook is Script {
    PoolManager manager =
        PoolManager(0x5FbDB2315678afecb367f032d93F642f64180aa3);
    PoolSwapTest swapRouter =
        PoolSwapTest(0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512);
    PoolModifyLiquidityTest modifyLiquidityRouter =
        PoolModifyLiquidityTest(0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0);

    Currency token0;
    Currency token1;
    Currency stableCoin;
    MockERC20 USDC;

    PoolKey key;

    uint256 privateKey;
    address signerAddr;

    function setUp() public {
        privateKey = vm.envUint("PRIVATE_KEY");
        signerAddr = vm.addr(privateKey);
        vm.startBroadcast(privateKey);

        MockERC20 tokenA = new MockERC20("Token0", "TK0", 18);
        tokenA.mint(signerAddr, 100000e18);
        MockERC20 tokenB = new MockERC20("Token1", "TK1", 18);
        tokenB.mint(signerAddr, 100000e18);

        (token0, token1) = (
            Currency.wrap(address(tokenA)),
            Currency.wrap(address(tokenB))
        );

        USDC = new MockERC20("USDC", "USDC", 6);
        stableCoin = Currency.wrap(address(USDC));

        tokenA.approve(address(modifyLiquidityRouter), type(uint256).max);
        tokenB.approve(address(modifyLiquidityRouter), type(uint256).max);
        stableCoin.approve(address(modifyLiquidityRouter), type(uint256).max);

        tokenA.approve(address(swapRouter), type(uint256).max);
        tokenB.approve(address(swapRouter), type(uint256).max);
        stableCoin.approve(address(swapRouter), type(uint256).max);

        vm.stopBroadcast();
        // Requires currency0 and currency1 to be set in base Deployers contract.
        //deployAndApprovePosm(manager);
        //approvePosmCurrency(stableCoin);
        //_initPoolsForStableCoin();
        _initPoolsForStableCoin();
        //seedBalance(alice);
        //approvePosmFor(alice);

        // Mine for hook address

        uint160 flags = uint160(Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_SWAP_FLAG);
        address hookAddress = address(flags);

        /**address CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
        (address hookAddress, bytes32 salt) = HookMiner.find(
            CREATE2_DEPLOYER,
            flags,
            type(PoolPartyDynamicShieldHook).creationCode,
            abi.encode(address(manager))
        );**/
    }

    function run() public {
        vm.startBroadcast();
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -120,
                tickUpper: 120,
                liquidityDelta: 10e18,
                salt: 0
            }),
            new bytes(0)
        );
        vm.stopBroadcast();
    }

    function _initPoolsForStableCoin() internal {
        // Load configuration from environment or hardcode for testing
        uint256 usdcAmount = 2000000e6;
        uint24 fee = 3000;

        vm.startBroadcast();

        // Mint USDC
        USDC.mint(msg.sender, usdcAmount);

        // Approve tokens for liquidity router
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

        // Initialize token0/USDC pool and add liquidity
        PoolKey memory token0USDCKey = initPoolUnsorted(
            token0,
            stableCoin,
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
            Constants.ZERO_BYTES
        );

        // Initialize token1/USDC pool and add liquidity
        PoolKey memory token1USDCKey = initPoolUnsorted(
            stableCoin,
            token1,
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

        vm.stopBroadcast();
    }
}
