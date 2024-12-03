## PoolPartyDynamicShieldHook

**The PoolPartyDynamicShieldHook project introduces dynamic, customizable logic to Uniswap liquidity pools by leveraging Uniswap v4's hook system. The goal is to provide advanced control and monitoring during swaps, enabling features like dynamic shielding, access control, or additional security layers for liquidity providers and traders.**

Foundry consists of:

- **Forge**: Ethereum testing framework
- **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
- **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
- **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Libraries

```shell
forge install foundry-rs/forge-std
forge install uniswap/v4-core
forge install uniswap/v4-periphery
forge install openzeppelin/openzeppelin-contracts
forge install transmissions11/solmate
```

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Deploy with Anvil

```shell
$ anvil
```

V4 Uniswap Core

```shell
$ forge script script/DeployV4Core.sol --fork-url http://127.0.0.1:8545 --broadcast --private-key <PRIVATE_KEY>
```

Deployed PoolManager at 0x5FbDB2315678afecb367f032d93F642f64180aa3
Deployed PoolSwapTest at 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512
Deployed PoolModifyLiquidityTest at 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0
Deployed PoolDonateTest at 0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9
Deployed PoolTakeTest at 0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9
Deployed PoolClaimsTest at 0x5FC8d32690cc91D4c39d9d3abcBD16989F875707

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
