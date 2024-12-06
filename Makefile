NETWORK_ARGS := --rpc-url $(RPC_URL) --private-key $(DEPLOYER_PRIVATE_KEY) --broadcast

deploy:
	forge build
	npm run extract:abis
	npm run deploy:core
	npm run deploy:pool-vault-mg

deploy-simulator:
	forge script script/DeploySimulateHook.s.sol --tc DeploySimulateHook  --fork-url http://127.0.0.1:8547 --broadcast

registerShield:
	cast send 0x6437f6bb3087341f44099be940bdc82d5994376a --rpc-url http://localhost:8547 \
    --private-key 0xb6b15c8cb491557369f3c7d2c287b053eb229daa9c22138887752191c9520659 \
		"registerShield(bytes32,int24,int24,uint256,address)" \
		-- "0xf49112cf8195ae8535e23af5a39b0a8102abd893288f40d95f5b64c4f50bb63c" -5000 5000 315 "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
    
registerShield2:
	cast send 0x6437f6bb3087341f44099be940bdc82d5994376a --rpc-url http://localhost:8547 \
    --private-key 0xb6b15c8cb491557369f3c7d2c287b053eb229daa9c22138887752191c9520659 \
		"registerShield(bytes32,int24,int24,uint256,address)" \
		-- "0xf49112cf8195ae8535e23af5a39b0a8102abd893288f40d95f5b64c4f50bb63A" 5000 15000 316 "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
    

sendTickEvent:
	cast send 0x6437f6bb3087341f44099be940bdc82d5994376a --rpc-url http://localhost:8547 \
    --private-key 0xb6b15c8cb491557369f3c7d2c287b053eb229daa9c22138887752191c9520659 \
		"sendTickEvent(bytes32,int24)" \
		-- "0xf49112cf8195ae8535e23af5a39b0a8102abd893288f40d95f5b64c4f50bb63c" 6000
    
sendTickEvent2:
	cast send 0x6437f6bb3087341f44099be940bdc82d5994376a --rpc-url http://localhost:8547 \
    --private-key 0xb6b15c8cb491557369f3c7d2c287b053eb229daa9c22138887752191c9520659 \
		"sendTickEvent(bytes32,int24)" \
		-- "0xf49112cf8195ae8535e23af5a39b0a8102abd893288f40d95f5b64c4f50bb63A" -5000

removeIndex:
	cast call 0x6437f6bb3087341f44099be940bdc82d5994376a \
			"getRemoveIndex()(uint256)"  --rpc-url http://localhost:8547

tokenIds:
	cast call 0x6437f6bb3087341f44099be940bdc82d5994376a \
			"getTokenIds()(uint256[])"  --rpc-url http://localhost:8547

call:
	make removeIndex
	make tokenIds
