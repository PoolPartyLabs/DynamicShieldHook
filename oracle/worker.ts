import boss, { queueName } from './queue';

async function startWorker() {
  await boss.work(queueName, async ([ job ]) => {
    console.log(`received job ${job.id} with data ${JSON.stringify(job.data)}`)

    // TODO:  send mesage to Smart Contract
    
    await boss.deleteJob(queueName, job.id)
  })
}

startWorker();
