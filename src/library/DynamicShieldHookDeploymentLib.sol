// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";

import {PoolPartyDynamicShieldHook} from "../PoolPartyDynamicShieldHook.sol";
import {IPoolPartyDynamicShieldHook} from "../interfaces/IPoolPartyDynamicShieldHook.sol";
import {IFeeManager} from "../interfaces/IFeeManager.sol";

import {HookMiner} from "../../utils/HookMiner.sol";

library DynamicShieldHookDeploymentLib {
    using stdJson for *;
    using Strings for *;

    Vm internal constant vm =
        Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    struct DeploymentData {
        address dynamicShield;
    }

    function deployContracts(
        IPoolManager _poolManager,
        IPositionManager _positionManager,
        IAllowanceTransfer _permit2,
        IFeeManager _feeManager,
        Currency _safeToken,
        uint24 _feeInit,
        uint24 _feeMax,
        address _initialOwner
    ) internal returns (DeploymentData memory) {
        DeploymentData memory result;

        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG |
                Hooks.BEFORE_SWAP_FLAG |
                Hooks.AFTER_SWAP_FLAG
        );

        // Find an address + salt using HookMiner that meets our flags criteria
        address CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
        (address hookAddress, bytes32 salt) = HookMiner.find(
            CREATE2_DEPLOYER,
            flags,
            type(PoolPartyDynamicShieldHook).creationCode,
            abi.encode(
                _poolManager,
                _positionManager,
                _permit2,
                _feeManager,
                _safeToken,
                _feeInit,
                _feeMax,
                _initialOwner
            )
        );

        result.dynamicShield = address(
            new PoolPartyDynamicShieldHook{salt: salt}(
                _poolManager,
                _positionManager,
                _permit2,
                _feeManager,
                _safeToken,
                _feeInit,
                _feeMax,
                _initialOwner
            )
        );

        // Ensure it got deployed to our pre-computed address
        require(
            address(result.dynamicShield) == hookAddress,
            "hook address mismatch"
        );

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
        data.dynamicShield = json.readAddress(".addresses.dynamicShield");
        return data;
    }

    /// write to default output path
    function writeDeploymentJson(DeploymentData memory data) internal {
        writeDeploymentJson(
            "deployments/dynamic-shield-hook/",
            block.chainid,
            data
        );
    }

    function writeDeploymentJson(
        string memory outputPath,
        uint256 chainId,
        DeploymentData memory data
    ) internal {
        string memory deploymentData = _generateDeploymentJson(data);

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
        DeploymentData memory data
    ) private view returns (string memory) {
        return
            string.concat(
                '{"lastUpdate":{"timestamp":"',
                vm.toString(block.timestamp),
                '","block_number":"',
                vm.toString(block.number),
                '"},"addresses":',
                _generateContractsJson(data),
                "}"
            );
    }

    function _generateContractsJson(
        DeploymentData memory data
    ) private pure returns (string memory) {
        return
            string.concat(
                '{"dynamicShield":"',
                data.dynamicShield.toHexString(),
                '"}'
            );
    }
}
