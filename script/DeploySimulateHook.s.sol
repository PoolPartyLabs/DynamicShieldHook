// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

contract DeploySimulateHook is Script {
    function run() public {
        // uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        // vm.startBroadcast(deployerPrivateKey);
        // SimulateHook hook = new SimulateHook();
        // console.log("SimulateHook deployed to:", address(hook));
        // vm.stopBroadcast();
    }
}

/**
 * 

registerShield:
	cast send 0x5FbDB2315678afecb367f032d93F642f64180aa3 --rpc-url http://localhost:8545 \
    --private-key 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a \
		"registerShield(bytes32,int24,int24,uint256,address)" \
		-- "0xf49112cf8195ae8535e23af5a39b0a8102abd893288f40d95f5b64c4f50bb63c" -5000 5000 300 "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
    
sendTickEvent:
	cast send 0x5FbDB2315678afecb367f032d93F642f64180aa3 --rpc-url http://localhost:8545 \
    --private-key 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a \
		"sendTickEvent(bytes32,int24)" \
		-- "0xf49112cf8195ae8535e23af5a39b0a8102abd893288f40d95f5b64c4f50bb63c" -5000
    

reomvedTokenIds:
    cast call 0x5FbDB2315678afecb367f032d93F642f64180aa3 --rpc-url http://localhost:8545 \
    "reomvedTokenIds(uint256,bytes32)" \ 
    1 "0xf49112cf8195ae8535e23af5a39b0a8102abd893288f40d95f5b64c4f50bb63c"


 * 
 */
