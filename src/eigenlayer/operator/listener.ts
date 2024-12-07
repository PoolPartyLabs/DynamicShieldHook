import { createPublicClient, http, parseAbiItem } from "viem";
import { mainnet, foundry } from "viem/chains";
import boss, { queueName } from "./queue";
import { createTable, _knex } from "./repository";
import { CONTRACT, RPC_PROVIDER } from "./constants";

const publicClient = createPublicClient({
  chain: foundry,
  transport: http(RPC_PROVIDER),
});

const blockNumber = await publicClient.getBlockNumber();
let lastBlock = blockNumber;
console.log(`lastBlock: ${lastBlock}`);

async function start() {
  await createTable();
  // TODO: handle the unwatch in the future
  const unwatch = publicClient.watchEvent({
    address: CONTRACT,
    poll: true,
    pollingInterval: 5_000, // 5 seconds
    fromBlock: lastBlock,
    events: [
      parseAbiItem([
        "event TickEvent(bytes32 indexed poolId, int24 indexed currentTick, uint32 indexed taskIndex, Task task)",
        "struct Task { uint32 taskIndex;  bytes32 poolId;  uint32 taskCreatedBlock; }",
      ]),
      parseAbiItem(
        "event RegisterShieldEvent(bytes32 poolId, int24 tickLower, int24 tickUpper, uint256 tokenId, address owner)"
      ),
    ],
    onLogs: async (logs) => {
      console.log(logs);
      console.log(`lastBlock: ${lastBlock}`);
      const log = logs?.length > 1 ? logs[logs?.length - 1] : logs[0];
      const { blockNumber, args, eventName } = log;
      lastBlock = blockNumber;
      console.log(eventName, args);

      if (eventName === "TickEvent") {
        const poolId = args.poolId;
        const currentTick = args.currentTick;
        const taskIndex = args.taskIndex;
        const task = args.task;
        console.log(`poolId: ${poolId}, currentTick: ${currentTick}`);
        const id = await boss.send(queueName, {
          poolId,
          currentTick,
          taskIndex,
          task,
        });

        console.log(`created job ${id} in queue ${queueName}`);
      } else if (eventName === "RegisterShieldEvent") {
        const poolId = args.poolId;
        const tickLower = args.tickLower;
        const tickUpper = args.tickUpper;
        const tokenId = args.tokenId;
        const owner = args.owner;
        console.log(
          `poolId: ${poolId}, tickLower: ${tickLower}, tickUpper: ${tickUpper}, tokenId: ${tokenId}, owner: ${owner}`
        );
        try {
          await _knex
            .insert({
              pool_id: poolId,
              token_id: tokenId,
              tick_low: args.tickLower,
              tick_upper: args.tickUpper,
            })
            .into("shields");
        } catch (e) {
          console.log(e);
        }
      }
    },
    onError: (error) => console.error(error),
  });
}

start();
