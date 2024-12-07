// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/Test.sol";

import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {StrategyFactory} from "@eigenlayer/contracts/strategies/StrategyFactory.sol";
import {StrategyBase} from "@eigenlayer/contracts/strategies/StrategyBase.sol";
import {StrategyManager} from "@eigenlayer/contracts/core/StrategyManager.sol";
import {Quorum, StrategyParams, IStrategy} from "@eigenlayer-middleware/src/interfaces/IECDSAStakeRegistryEventsAndErrors.sol";

import {DynamicShieldAVSDeploymentLib} from "../src/eigenlayer/library/DynamicShieldAVSDeploymentLib.sol";
import {CoreDeploymentLib} from "../src/eigenlayer/library/CoreDeploymentLib.sol";
import {DynamicShieldHookDeploymentLib} from "../src/library/DynamicShieldHookDeploymentLib.sol";
import {UpgradeableProxyLib} from "../src/library/UpgradeableProxyLib.sol";
import {IPoolPartyDynamicShieldHook} from "../src/interfaces/IPoolPartyDynamicShieldHook.sol";

contract DynamicShieldAVSDeployer is Script {
    using CoreDeploymentLib for *;
    using UpgradeableProxyLib for address;

    address private deployer;
    address proxyAdmin;
    IStrategy dynamicShieldAVSStrategy;
    CoreDeploymentLib.DeploymentData coreDeployment;
    DynamicShieldAVSDeploymentLib.DeploymentData dynamicShieldAVSDeployment;
    DynamicShieldHookDeploymentLib.DeploymentData dynamicShieldHookDeployment;
    Quorum internal quorum;
    MockERC20 token;

    function setUp() public virtual {
        deployer = vm.rememberKey(vm.envUint("PRIVATE_KEY"));
        vm.label(deployer, "Deployer");

        coreDeployment = CoreDeploymentLib.readDeploymentJson(
            "deployments/core/",
            block.chainid
        );

        token = new MockERC20("USDC", "USDC", 6);
        dynamicShieldAVSStrategy = IStrategy(
            StrategyFactory(coreDeployment.strategyFactory).deployNewStrategy(
                IERC20(address(token))
            )
        );

        quorum.strategies.push(
            StrategyParams({
                strategy: dynamicShieldAVSStrategy,
                multiplier: 10_000
            })
        );

        dynamicShieldHookDeployment = DynamicShieldHookDeploymentLib
            .readDeploymentJson(
                "deployments/dynamic-shield-hook/",
                block.chainid
            );
    }

    function run() external {
        vm.startBroadcast(deployer);
        proxyAdmin = UpgradeableProxyLib.deployProxyAdmin(deployer);

        dynamicShieldAVSDeployment = DynamicShieldAVSDeploymentLib
            .deployContracts(
                deployer,
                IPoolPartyDynamicShieldHook(
                    dynamicShieldHookDeployment.dynamicShield
                ),
                coreDeployment,
                quorum
            );

        IPoolPartyDynamicShieldHook(dynamicShieldHookDeployment.dynamicShield)
            .registerAVS(dynamicShieldAVSDeployment.dynamicShieldAVS);

        dynamicShieldAVSDeployment.strategy = address(dynamicShieldAVSStrategy);
        dynamicShieldAVSDeployment.token = address(token);
        vm.stopBroadcast();

        verifyDeployment();
        DynamicShieldAVSDeploymentLib.writeDeploymentJson(
            dynamicShieldAVSDeployment
        );
    }

    function verifyDeployment() internal view {
        require(
            dynamicShieldAVSDeployment.stakeRegistry != address(0),
            "StakeRegistry address cannot be zero"
        );
        require(
            dynamicShieldAVSDeployment.dynamicShieldAVS != address(0),
            "DynamicShieldAVS address cannot be zero"
        );
        require(
            dynamicShieldAVSDeployment.strategy != address(0),
            "Strategy address cannot be zero"
        );
        require(proxyAdmin != address(0), "ProxyAdmin address cannot be zero");
        require(
            coreDeployment.delegationManager != address(0),
            "DelegationManager address cannot be zero"
        );
        require(
            coreDeployment.avsDirectory != address(0),
            "AVSDirectory address cannot be zero"
        );
    }
}
