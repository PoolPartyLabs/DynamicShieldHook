// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {Script} from "forge-std/Script.sol";

import {CoreDeploymentLib} from "../src/eigenlayer/library/CoreDeploymentLib.sol";
import {UpgradeableProxyLib} from "../src/library/UpgradeableProxyLib.sol";

contract DeployEigenLayerCore is Script {
    using CoreDeploymentLib for *;
    using UpgradeableProxyLib for address;

    address internal deployer;
    address internal proxyAdmin;
    CoreDeploymentLib.DeploymentData internal deploymentData;
    CoreDeploymentLib.DeploymentConfigData internal configData;

    function setUp() public virtual {
        deployer = vm.rememberKey(vm.envUint("PRIVATE_KEY"));
        vm.label(deployer, "Deployer");
    }

    function run() external {
        vm.startBroadcast(deployer);
        proxyAdmin = UpgradeableProxyLib.deployProxyAdmin(deployer);
        deploymentData = CoreDeploymentLib.deployContracts(deployer, configData);
        vm.stopBroadcast();
        string memory deploymentPath = "deployments/core/";
        CoreDeploymentLib.writeDeploymentJson(deploymentPath, block.chainid, deploymentData);
    }
}
