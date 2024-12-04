// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

contract SimulateHook {
    uint256 public removeIndex;
    mapping(uint256 removeIndex => mapping(bytes32 poolId => uint256[] tokenIds))
        public reomvedTokenIds;
    uint256[] public tokenIds;

    event TickEvent(bytes32 poolId, int24 currentTick);

    event RegisterShieldEvent(
        bytes32 poolId,
        int24 feeMaxLow,
        int24 feeMaxUpper,
        uint256 tokenId,
        address owner
    );

    function registerShield(
        bytes32 poolId,
        int24 feeMaxLow,
        int24 feeMaxUpper,
        uint256 tokenId,
        address owner
    ) external {
        emit RegisterShieldEvent(
            poolId,
            feeMaxLow,
            feeMaxUpper,
            tokenId,
            owner
        );
    }

    function sendTickEvent(bytes32 poolId, int24 currentTick) external {
        emit TickEvent(poolId, currentTick);
    }

    function removeLiquidityInBatch(
        bytes32 poolId,
        uint256[] memory _tokenIds
    ) external {
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            tokenIds.push(_tokenIds[i]);
            reomvedTokenIds[removeIndex][poolId].push(_tokenIds[i]);
        }
        removeIndex++;
    }

    function getRemoveIndex() external view returns (uint256) {
        return removeIndex;
    }

    function getRemovedTokenIds(
        uint256 index,
        bytes32 poolId
    ) external view returns (uint256[] memory) {
        return reomvedTokenIds[index][poolId];
    }

    function getTokenIds() external view returns (uint256[] memory) {
        return tokenIds;
    }
}

contract DeploySimulateHook is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        SimulateHook hook = new SimulateHook();
        console.log("SimulateHook deployed to:", address(hook));
        vm.stopBroadcast();
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
