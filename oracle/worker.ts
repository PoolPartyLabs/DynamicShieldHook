import boss, { queueName } from "./queue";
import { createWalletClient, http, publicActions } from "viem";
import { mainnet, foundry } from "viem/chains";
import { privateKeyToAccount } from "viem/accounts";
import { _knex } from "./repository";
import { ABI } from "./ABI";
import { RPC_PROVIDER, PRIVATE_KEY, CONTRACT } from "./constants";

const account = privateKeyToAccount(PRIVATE_KEY);

export const walletClient = createWalletClient({
  account,
  chain: foundry,
  transport: http(RPC_PROVIDER),
}).extend(publicActions);

async function startWorker() {
  await boss.work(queueName, async ([job]) => {
    console.log(`received job ${job.id} with data ${JSON.stringify(job.data)}`);
    await boss.deleteJob(queueName, job.id);

    try {
      const { poolId, currentTick } = job.data as any;
      const tokenIds = await _knex("shields")
        .select("token_id")
        .where("pool_id", "=", poolId)
        .andWhere("tick_low", ">", currentTick)
        .orWhere("tick_upper", "<", currentTick)
        .limit(500);
      console.log(`tokenIds: ${JSON.stringify(tokenIds)}`);

      if (tokenIds.length === 0) {
        return;
      }
      const stringTokenIds = tokenIds.map((tokenId) => `${tokenId.token_id}`);
      const bigIntTokenIds: BigInt[] = Array.from(new Set(stringTokenIds)).map(
        (tokenId) => BigInt(tokenId)
      );
      const { request } = await walletClient.simulateContract({
        address: CONTRACT,
        abi: ABI,
        functionName: "removeLiquidityInBatch",
        args: [poolId, bigIntTokenIds],
      });
      const hash = await walletClient.writeContract(request); // Wallet Action
      console.log(`transaction hash: ${hash}`);
    } catch (error) {
      console.error(error);
    }
  });
}

startWorker();
