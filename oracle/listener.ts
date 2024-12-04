import { createPublicClient, http, parseAbiItem } from "viem";
import { mainnet, foundry } from "viem/chains";
import boss, { queueName } from "./queue";
import { createTable, _knex } from "./repository";
import { CONTRACT, RPC_PROVIDER } from './constants';

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
      parseAbiItem("event TickEvent(bytes32 poolId, int24 currentTick)"),
      parseAbiItem(
        "event RegisterShieldEvent(bytes32 poolId, int24 feeMaxLow, int24 feeMaxUpper, uint256 tokenId, address owner)"
      ),
    ],
    onLogs: async (logs) => {
      console.log(`lastBlock: ${lastBlock}`); 
      const log = logs?.length > 1 ? logs[logs?.length - 1] : logs[0];
      const { blockNumber, args, eventName } = log;
      lastBlock = blockNumber;
      console.log(eventName, args);

      if (eventName === "TickEvent") {
        const poolId = args.poolId;
        const currentTick = args.currentTick;
        console.log(`poolId: ${poolId}, currentTick: ${currentTick}`);
        const id = await boss.send(queueName, {
          poolId,
          currentTick,
        });

        console.log(`created job ${id} in queue ${queueName}`);
      } else if (eventName === "RegisterShieldEvent") {
        const poolId = args.poolId;
        const feeMaxLow = args.feeMaxLow;
        const feeMaxUpper = args.feeMaxUpper;
        const tokenId = args.tokenId;
        const owner = args.owner;
        console.log(
          `poolId: ${poolId}, feeMaxLow: ${feeMaxLow}, feeMaxUpper: ${feeMaxUpper}, tokenId: ${tokenId}, owner: ${owner}`
        );
        try {
          await _knex
            .insert({
              pool_id: poolId,
              token_id: tokenId,
              tick_low: args.feeMaxLow,
              tick_upper: args.feeMaxUpper,
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
