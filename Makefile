integration-test-pool-party-position-manager-contract:
	forge test --fork-url $(FORK_RPC_URL) --fork-block-number $(FORK_BLOCK_NUMBER) --evm-version cancun \
		--match-path test/integration/PoolPartyPositionManager.t.sol --match-contract PoolPartyPositionManagerTest \
		--match-test test_moveRange \
		--via-ir -vv

NETWORK_ARGS := --rpc-url $(RPC_URL) --private-key $(DEPLOYER_PRIVATE_KEY) --broadcast

UPGRADE_NETWORK_ARGS := --rpc-url $(RPC_URL) --private-key $(UPGRADER_PRIVATE_KEY) --broadcast
 
NETWORK_ARGS_WITH_VERIFY := $(NETWORK_ARGS) --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv

UPGRADE_NETWORK_ARGS_WITH_VERIFY := $(UPGRADE_NETWORK_ARGS) --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv


send-ether:
	cast send 0xd76906f47b35CfcE775ff11bb7812C83fB3B16a8 --value 10ether --private-key 0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6
 
mint:
	cast send 0x5FbDB2315678afecb367f032d93F642f64180aa3 "mint(address, uint256)"  "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC" 10000000000000000000000000  --rpc-url $(RPC_URL) --private-key 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a
 
transfer:
	cast send 0x5FbDB2315678afecb367f032d93F642f64180aa3 "transfer(address,uint256)" "0x1A91736A8d1beACcf0C251BE192b866a1621f5a1" 500000000   --rpc-url $(RPC_URL) --private-key 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a
	   
balance:
	cast call 0x5FbDB2315678afecb367f032d93F642f64180aa3 "balanceOf(address)" 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC  --rpc-url $(RPC_URL) 
 