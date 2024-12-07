include .env.devnet

export $(shell sed 's/=.*//' .env.devnet)

NETWORK_ARGS := --rpc-url $(RPC_URL) --private-key $(DEPLOYER_PRIVATE_KEY) --broadcast

start-anvil:
	anvil --fork-url $(FORK_RPC_URL) --chain-id 31337

deploy-eigenlayer-core:
	forge script script/DeployEigenLayerCore.s.sol $(NETWORK_ARGS)

deploy-eigenlayer-avs:
	forge script script/DynamicShieldAVSDeployer.s.sol $(NETWORK_ARGS)

deploy-hook:
	forge script script/DeployPoolPartyDynamicShieldHook.s.sol $(NETWORK_ARGS)

deploy:
	make deploy-eigenlayer-core
	make deploy-hook
	# make deploy-eigenlayer-avs
	# cd src/eigenlayer && npm run extract:abis 

notifyRegisterShield:
		cast send 0xd688bf9cd0d90481988a889288136c4466f31ffb "notifyRegisterShield(bytes32, int24, int24, uint256)" \
		--private-key $(DEPLOYER_PRIVATE_KEY) --rpc-url $(RPC_URL)   \
		-- "0xf49112cf8195ae8535e23af5a39b0a8102abd893288f40d95f5b64c4f50bb63A" -90 90 10001

notifyTickEvent:
		cast send 0xd688bf9cd0d90481988a889288136c4466f31ffb "notifyTickEvent(bytes32, int24)" \
		--private-key $(DEPLOYER_PRIVATE_KEY) --rpc-url $(RPC_URL)   \
		-- "0xf49112cf8195ae8535e23af5a39b0a8102abd893288f40d95f5b64c4f50bb63A" -91


