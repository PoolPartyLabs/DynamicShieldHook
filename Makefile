include .env.devnet

export $(shell sed 's/=.*//' .env.devnet)

NETWORK_ARGS := --rpc-url $(RPC_URL) --private-key $(DEPLOYER_PRIVATE_KEY) --broadcast

deploy:
	forge build
	npm run extract:abis
	npm run deploy:core
	npm run deploy:avs
