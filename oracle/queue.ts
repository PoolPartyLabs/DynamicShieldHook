import PgBoss from "pg-boss";
import { DB_URI } from "./constants";

const boss = new PgBoss({
  connectionString: DB_URI,
});

export const queueName = "tick-event";

async function initBoss() {
  await boss.start();
  console.log("PgBoss started");
  await boss.createQueue(queueName);
  console.log(`created queue ${queueName}`);
}

initBoss();

export default boss;
