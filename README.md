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
forge install solmate/solmate
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

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/... --rpc-url <your_rpc_url> --private-key <your_private_key>
```

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
