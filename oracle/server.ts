import { createPublicClient, webSocket, http, parseAbiItem } from "viem";
import { mainnet } from "viem/chains";
import boss, { queueName } from "./queue";

const publicClient = createPublicClient({
  chain: mainnet,
  // transport: webSocket('wss://arbitrum-mainnet.infura.io/ws/v3/501147213910491093350972b603e065', {
  //   keepAlive: { interval: 1_000 },
  //   reconnect: {
  //     attempts: 10,
  //   }
  // }),
  transport: http(process.env.RPC_PROVIDER),
});

const blockNumber = await publicClient.getBlockNumber();
let lastBlock = blockNumber;
console.log(`lastBlock: ${lastBlock}`);

const unwatch = publicClient.watchEvent({
  address: `0x${process.env.CONTRACT}` || `0x000`,
  poll: true,
  pollingInterval: 5_000, // 5 seconds
  fromBlock: lastBlock,
  event: parseAbiItem(
    "event Transfer(address indexed from, address indexed to, uint256 value)"
  ),
  onLogs: async (logs) => {
    console.log(`lastBlock: ${lastBlock}`);
    console.log(logs?.length);
    const log = logs?.length > 1 ? logs[logs?.length - 1] : logs[0];
    console.log(log);
    const { blockNumber, args } = log;
    lastBlock = blockNumber;

    const from = args.from;
    const to = args.to;
    const value = args.value;

    const id = await boss.send(queueName, {
      from,
      to,
      value: value.toString(),
    });

    console.log(`created job ${id} in queue ${queueName}`);
  },
  onError: (error) => console.error(error),
});
