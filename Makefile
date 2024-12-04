NETWORK_ARGS := --rpc-url $(RPC_URL) --private-key $(DEPLOYER_PRIVATE_KEY) --broadcast

deploy-simulator:
	forge script script/DeploySimulateHook.s.sol --tc DeploySimulateHook  --fork-url http://127.0.0.1:8545 --broadcast

registerShield:
	cast send 0x5FbDB2315678afecb367f032d93F642f64180aa3 --rpc-url http://localhost:8545 \
    --private-key 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a \
		"registerShield(bytes32,int24,int24,uint256,address)" \
		-- "0xf49112cf8195ae8535e23af5a39b0a8102abd893288f40d95f5b64c4f50bb63c" -5000 5000 300 "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
    
registerShield2:
	cast send 0x5FbDB2315678afecb367f032d93F642f64180aa3 --rpc-url http://localhost:8545 \
    --private-key 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a \
		"registerShield(bytes32,int24,int24,uint256,address)" \
		-- "0xf49112cf8195ae8535e23af5a39b0a8102abd893288f40d95f5b64c4f50bb63A" 5000 15000 301 "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
    

sendTickEvent:
	cast send 0x5FbDB2315678afecb367f032d93F642f64180aa3 --rpc-url http://localhost:8545 \
    --private-key 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a \
		"sendTickEvent(bytes32,int24)" \
		-- "0xf49112cf8195ae8535e23af5a39b0a8102abd893288f40d95f5b64c4f50bb63c" 6000
    
sendTickEvent2:
	cast send 0x5FbDB2315678afecb367f032d93F642f64180aa3 --rpc-url http://localhost:8545 \
    --private-key 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a \
		"sendTickEvent(bytes32,int24)" \
		-- "0xf49112cf8195ae8535e23af5a39b0a8102abd893288f40d95f5b64c4f50bb63A" -5000

removeIndex:
	cast call 0x5FbDB2315678afecb367f032d93F642f64180aa3 \
			"getRemoveIndex()(uint256)"  --rpc-url http://localhost:8545

tokenIds:
	cast call 0x5FbDB2315678afecb367f032d93F642f64180aa3 \
			"getTokenIds()(uint256[])"  --rpc-url http://localhost:8545

call:
	make removeIndex
	make tokenIds
