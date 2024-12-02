import PgBoss from "pg-boss";

const boss = new PgBoss({
  host: "127.0.0.1",
  port: 5432,
  database: "blockchain_test",
  user: "your_database_user",
  password: "your_database_password",
});

export const queueName = "blockchain-event";

async function initBoss() {
  await boss.start();
  console.log("PgBoss started");
  await boss.createQueue(queueName);
  console.log(`created queue ${queueName}`);
}

initBoss();

export default boss;
