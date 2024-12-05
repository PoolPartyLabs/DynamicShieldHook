// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {console2} from "forge-std/Test.sol";
import {PoolVaultManagerDeploymentLib} from "./utils/PoolVaultManagerDeploymentLib.sol";
import {CoreDeploymentLib} from "./utils/CoreDeploymentLib.sol";
import {UpgradeableProxyLib} from "./utils/UpgradeableProxyLib.sol";
import {StrategyBase} from "@eigenlayer/contracts/strategies/StrategyBase.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {StrategyFactory} from "@eigenlayer/contracts/strategies/StrategyFactory.sol";
import {StrategyManager} from "@eigenlayer/contracts/core/StrategyManager.sol";

import {Quorum, StrategyParams, IStrategy} from "@eigenlayer-middleware/src/interfaces/IECDSAStakeRegistryEventsAndErrors.sol";

contract PoolVaultManagerDeployer is Script {
    using CoreDeploymentLib for *;
    using UpgradeableProxyLib for address;

    address private deployer;
    address proxyAdmin;
    IStrategy poolVaultManagerStrategy;
    CoreDeploymentLib.DeploymentData coreDeployment;
    PoolVaultManagerDeploymentLib.DeploymentData poolVaultManagerDeployment;
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
        poolVaultManagerStrategy = IStrategy(
            StrategyFactory(coreDeployment.strategyFactory).deployNewStrategy(
                IERC20(address(token))
            )
        );

        quorum.strategies.push(
            StrategyParams({
                strategy: poolVaultManagerStrategy,
                multiplier: 10_000
            })
        );
    }

    function run() external {
        vm.startBroadcast(deployer);
        proxyAdmin = UpgradeableProxyLib.deployProxyAdmin(deployer);

        poolVaultManagerDeployment = PoolVaultManagerDeploymentLib
            .deployContracts(deployer, coreDeployment, quorum);

        poolVaultManagerDeployment.strategy = address(poolVaultManagerStrategy);
        poolVaultManagerDeployment.token = address(token);
        vm.stopBroadcast();

        verifyDeployment();
        PoolVaultManagerDeploymentLib.writeDeploymentJson(
            poolVaultManagerDeployment
        );
    }

    function verifyDeployment() internal view {
        require(
            poolVaultManagerDeployment.stakeRegistry != address(0),
            "StakeRegistry address cannot be zero"
        );
        require(
            poolVaultManagerDeployment.poolVaultManager != address(0),
            "PoolVaultManager address cannot be zero"
        );
        require(
            poolVaultManagerDeployment.strategy != address(0),
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
