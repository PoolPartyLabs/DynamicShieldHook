export const ABI = [
  {
    type: "function",
    name: "registerShield",
    inputs: [
      {
        name: "poolId",
        type: "bytes32",
        internalType: "bytes32",
      },
      {
        name: "feeMaxLow",
        type: "int24",
        internalType: "int24",
      },
      {
        name: "feeMaxUpper",
        type: "int24",
        internalType: "int24",
      },
      {
        name: "tokenId",
        type: "uint256",
        internalType: "uint256",
      },
      {
        name: "owner",
        type: "address",
        internalType: "address",
      },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "removeLiquidityInBatch",
    inputs: [
      {
        name: "poolId",
        type: "bytes32",
        internalType: "bytes32",
      },
      {
        name: "_tokenIds",
        type: "uint256[]",
        internalType: "uint256[]",
      },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "reomvedTokenIds",
    inputs: [
      {
        name: "removeIndex",
        type: "uint256",
        internalType: "uint256",
      },
      {
        name: "poolId",
        type: "bytes32",
        internalType: "bytes32",
      },
      {
        name: "",
        type: "uint256",
        internalType: "uint256",
      },
    ],
    outputs: [
      {
        name: "tokenIds",
        type: "uint256",
        internalType: "uint256",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "sendTickEvent",
    inputs: [
      {
        name: "poolId",
        type: "bytes32",
        internalType: "bytes32",
      },
      {
        name: "currentTick",
        type: "int24",
        internalType: "int24",
      },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "event",
    name: "RegisterShieldEvent",
    inputs: [
      {
        name: "poolId",
        type: "bytes32",
        indexed: false,
        internalType: "bytes32",
      },
      {
        name: "feeMaxLow",
        type: "int24",
        indexed: false,
        internalType: "int24",
      },
      {
        name: "feeMaxUpper",
        type: "int24",
        indexed: false,
        internalType: "int24",
      },
      {
        name: "tokenId",
        type: "uint256",
        indexed: false,
        internalType: "uint256",
      },
      {
        name: "owner",
        type: "address",
        indexed: false,
        internalType: "address",
      },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "TickEvent",
    inputs: [
      {
        name: "poolId",
        type: "bytes32",
        indexed: false,
        internalType: "bytes32",
      },
      {
        name: "currentTick",
        type: "int24",
        indexed: false,
        internalType: "int24",
      },
    ],
    anonymous: false,
  },
];
