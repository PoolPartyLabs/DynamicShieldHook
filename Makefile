include .env.devnet

export $(shell sed 's/=.*//' .env.devnet)

NETWORK_ARGS := --rpc-url $(RPC_URL) --private-key $(DEPLOYER_PRIVATE_KEY) --broadcast

start-anvil:
	anvil --fork-url $(FORK_RPC_URL)

deploy-eigenlayer-core:
	forge script script/DeployEigenLayerCore.s.sol $(NETWORK_ARGS)

deploy-eigenlayer-avs:
	forge script script/DynamicShieldAVSDeployer.s.sol $(NETWORK_ARGS)

deploy-hook:
	forge script script/DeployPoolPartyDynamicShieldHook.s.sol $(NETWORK_ARGS)

deploy:
	make deploy-eigenlayer-core
	make deploy-hook
	make deploy-eigenlayer-avs
	cd src/eigenlayer && npm run extract:abis 
