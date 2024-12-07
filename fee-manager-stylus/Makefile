include .env

export $(shell sed 's/=.*//' .env)

start-testnode:
	cd ./nitro-testnode && bash ./test-node.bash --init

start-devnode:
	cd ./nitro-devnode && bash ./run-dev-node.sh

deploy:
	cargo stylus deploy --no-verify -e http://localhost:8547 \
		--private-key 0xb6b15c8cb491557369f3c7d2c287b053eb229daa9c22138887752191c9520659

updateFeePerTick:
		cast send 0xa6e41ffd769491a42a6e5ce453259b93983a22ef "updateFeePerTick(bytes32, uint128, int32, int32, uint32, uint32, uint32)" \
		--private-key 0xb6b15c8cb491557369f3c7d2c287b053eb229daa9c22138887752191c9520659 --rpc-url http://127.0.0.1:8547   \
		-- "0xf49112cf8195ae8535e23af5a39b0a8102abd893288f40d95f5b64c4f50bb63A" 12345999999 -90 90 10 500 10000

getFee:
		cast call 0xa6e41ffd769491a42a6e5ce453259b93983a22ef "getFee(bytes32, int32)(uint32)" \
		--private-key 0xb6b15c8cb491557369f3c7d2c287b053eb229daa9c22138887752191c9520659 --rpc-url http://127.0.0.1:8547 --gas-limit 200000000 \
		-- "0xf49112cf8195ae8535e23af5a39b0a8102abd893288f40d95f5b64c4f50bb63A" 0


getFees:
		cast call 0xa6e41ffd769491a42a6e5ce453259b93983a22ef "getFees(uint32, uint32, uint32)(uint32[])" \
		--private-key 0xb6b15c8cb491557369f3c7d2c287b053eb229daa9c22138887752191c9520659 --rpc-url http://127.0.0.1:8547 --gas-limit 200000000 \
		-- 181 500 10000

