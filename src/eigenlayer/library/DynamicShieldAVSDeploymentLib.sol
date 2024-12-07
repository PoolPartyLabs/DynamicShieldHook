// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {ECDSAStakeRegistry} from "@eigenlayer-middleware/src/unaudited/ECDSAStakeRegistry.sol";
import {IDelegationManager} from "@eigenlayer/contracts/interfaces/IDelegationManager.sol";
import {Quorum} from "@eigenlayer-middleware/src/interfaces/IECDSAStakeRegistryEventsAndErrors.sol";

import {UpgradeableProxyLib} from "../../library/UpgradeableProxyLib.sol";
import {IPoolPartyDynamicShieldHook} from "../../interfaces/IPoolPartyDynamicShieldHook.sol";
import {CoreDeploymentLib} from "./CoreDeploymentLib.sol";
import {DynamicShieldAVS} from "../DynamicShieldAVS.sol";

library DynamicShieldAVSDeploymentLib {
    using stdJson for *;
    using Strings for *;
    using UpgradeableProxyLib for address;

    Vm internal constant vm =
        Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    struct DeploymentData {
        address dynamicShieldAVS;
        address dynamicShieldHook;
        address stakeRegistry;
        address strategy;
        address token;
    }

    function deployContracts(
        address proxyAdmin,
        IPoolPartyDynamicShieldHook hook,
        CoreDeploymentLib.DeploymentData memory core,
        Quorum memory quorum
    ) internal returns (DeploymentData memory) {
        DeploymentData memory result;
        {
            result.dynamicShieldHook = address(hook);

            // console2.log(" DynamicShieldHook ", address(hook));

            // First, deploy upgradeable proxy contracts that will point to the implementations.
            result.dynamicShieldAVS = UpgradeableProxyLib.setUpEmptyProxy(
                proxyAdmin
            );
            result.stakeRegistry = UpgradeableProxyLib.setUpEmptyProxy(
                proxyAdmin
            );
        }
        // Deploy the implementation contracts, using the proxy contracts as inputs
        address stakeRegistryImpl = address(
            new ECDSAStakeRegistry(IDelegationManager(core.delegationManager))
        );
        address dynamicShieldAVSImpl = address(
            new DynamicShieldAVS(
                hook,
                core.avsDirectory,
                result.stakeRegistry,
                core.rewardsCoordinator,
                core.delegationManager
            )
        );
        {
            // Upgrade contracts
            bytes memory upgradeCall = abi.encodeCall(
                ECDSAStakeRegistry.initialize,
                (result.dynamicShieldAVS, 0, quorum)
            );
            UpgradeableProxyLib.upgradeAndCall(
                result.stakeRegistry,
                stakeRegistryImpl,
                upgradeCall
            );
            UpgradeableProxyLib.upgrade(
                result.dynamicShieldAVS,
                dynamicShieldAVSImpl
            );
        }
        return result;
    }

    function readDeploymentJson(
        uint256 chainId
    ) internal returns (DeploymentData memory) {
        return readDeploymentJson("deployments/", chainId);
    }

    function readDeploymentJson(
        string memory directoryPath,
        uint256 chainId
    ) internal returns (DeploymentData memory) {
        string memory fileName = string.concat(
            directoryPath,
            vm.toString(chainId),
            ".json"
        );

        require(vm.exists(fileName), "Deployment file does not exist");

        string memory json = vm.readFile(fileName);

        DeploymentData memory data;
        /// TODO: 2 Step for reading deployment json.  Read to the core and the AVS data
        data.dynamicShieldAVS = json.readAddress(".addresses.dynamicShieldAVS");
        data.stakeRegistry = json.readAddress(".addresses.stakeRegistry");
        data.strategy = json.readAddress(".addresses.strategy");
        data.token = json.readAddress(".addresses.token");
        data.dynamicShieldHook = json.readAddress(
            ".addresses.dynamicShieldHook"
        );

        return data;
    }

    /// write to default output path
    function writeDeploymentJson(DeploymentData memory data) internal {
        writeDeploymentJson(
            "deployments/dynamic-shield-avs/",
            block.chainid,
            data
        );
    }

    function writeDeploymentJson(
        string memory outputPath,
        uint256 chainId,
        DeploymentData memory data
    ) internal {
        address proxyAdmin = address(
            UpgradeableProxyLib.getProxyAdmin(data.dynamicShieldAVS)
        );

        string memory deploymentData = _generateDeploymentJson(
            data,
            proxyAdmin
        );

        string memory fileName = string.concat(
            outputPath,
            vm.toString(chainId),
            ".json"
        );
        if (!vm.exists(outputPath)) {
            vm.createDir(outputPath, true);
        }

        vm.writeFile(fileName, deploymentData);
        console2.log("Deployment artifacts written to:", fileName);
    }

    function _generateDeploymentJson(
        DeploymentData memory data,
        address proxyAdmin
    ) private view returns (string memory) {
        return
            string.concat(
                '{"lastUpdate":{"timestamp":"',
                vm.toString(block.timestamp),
                '","block_number":"',
                vm.toString(block.number),
                '"},"addresses":',
                _generateContractsJson(data, proxyAdmin),
                "}"
            );
    }

    function _generateContractsJson(
        DeploymentData memory data,
        address proxyAdmin
    ) private view returns (string memory) {
        return
            string.concat(
                '{"proxyAdmin":"',
                proxyAdmin.toHexString(),
                '","dynamicShieldAVS":"',
                data.dynamicShieldAVS.toHexString(),
                '","dynamicShieldAVSImpl":"',
                data.dynamicShieldAVS.getImplementation().toHexString(),
                '","stakeRegistry":"',
                data.stakeRegistry.toHexString(),
                '","stakeRegistryImpl":"',
                data.stakeRegistry.getImplementation().toHexString(),
                '","strategy":"',
                data.strategy.toHexString(),
                '","token":"',
                data.strategy.toHexString(),
                '","dynamicShieldHook":"',
                data.dynamicShieldHook.toHexString(),
                '"}'
            );
    }
}