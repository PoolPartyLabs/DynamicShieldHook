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
	make deploy-eigenlayer-avs
	cd src/eigenlayer && npm run extract:abis 

run-swap-hook:
	forge script script/RunSwapOnHook.s.sol $(NETWORK_ARGS)

read-hook-state:
	forge script script/ReadHookState.s.sol $(NETWORK_ARGS)

add-liquidity-hook:
	forge script script/AddLiquidityHook.s.sol $(NETWORK_ARGS)

notifyRegisterShield:
		cast send 0x84a94a689ea85b0c880bb61a62e3c6833d68262a "notifyRegisterShield(bytes32, int24, int24, uint256)" \
		--private-key $(DEPLOYER_PRIVATE_KEY) --rpc-url $(RPC_URL)   \
		-- "0x55b5ff0ce4f30d05703f9b4c20e14748dfc18a1ae715d3920c796311a589da70" 10 90 1

notifyTickEvent:
		cast send 0x84a94a689ea85b0c880bb61a62e3c6833d68262a "notifyTickEvent(bytes32, int24)" \
		--private-key $(DEPLOYER_PRIVATE_KEY) --rpc-url $(RPC_URL)   \
		-- "0xf49112cf8195ae8535e23af5a39b0a8102abd893288f40d95f5b64c4f50bb63A" -91

setPoolPartyDynamicShieldHook:
		cast send 0x84a94a689ea85b0c880bb61a62e3c6833d68262a "setPoolPartyDynamicShieldHook(address)" \
		--private-key $(DEPLOYER_PRIVATE_KEY) --rpc-url $(RPC_URL)   \
		-- "0xad7c02ac60cfa8ead46aa95580e9c0893871e0c0"
