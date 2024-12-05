import boss, { queueName } from "./queue";
import { ethers } from "ethers";
import { _knex } from "./repository";
import {
  registerOperator,
  wallet,
  provider,
  poolVaultManager,
} from "./eigenlayer";

async function startWorker() {
  await registerOperator();

  await boss.work(queueName, async ([job]) => {
    console.log(`received job ${job.id} with data ${JSON.stringify(job.data)}`);
    await boss.deleteJob(queueName, job.id);

    try {
      const { poolId, currentTick, taskIndex, task } = job.data as any;
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
      
      const messageHash = ethers.solidityPackedKeccak256(["bytes32"], [poolId]);
      const messageBytes = ethers.getBytes(messageHash);
      const signature = await wallet.signMessage(messageBytes);

      console.log(`Signing and responding to task ${taskIndex}`);

      const operators = [await wallet.getAddress()];
      console.log(`operators ${operators}`);
      const signatures = [signature];
      const signedTask = ethers.AbiCoder.defaultAbiCoder().encode(
        ["address[]", "bytes[]", "uint32"],
        [
          operators,
          signatures,
          ethers.toBigInt((await provider.getBlockNumber()) - 1),
        ]
      );

      const tx = await poolVaultManager.removeLiquidityInBatch(
        { taskIndex, poolId, taskCreatedBlock: task.taskCreatedBlock },
        taskIndex,
        bigIntTokenIds,
        signedTask
      );
      const hash = await tx.wait();
      console.log(`Responded to task.`);

      console.log(`Transaction hash: ${hash.blockHash}`);
    } catch (error) {
      console.error(error);
    }
  });
}

startWorker();
