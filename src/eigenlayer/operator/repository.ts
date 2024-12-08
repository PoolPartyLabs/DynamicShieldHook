import knex from "knex";
import { DB_URI } from './constants';

const ssl =
  process.env.NO_SSL?.toString() === "true"
    ? undefined
    : { rejectUnauthorized: false };

export const _knex = knex({
  client: "pg",
  connection: {
    connectionString: DB_URI,
    ssl,
  },
  pool: {
    min: 2,
    max: 10,
  },
});

export async function createTable() {
  const exists = await _knex.schema.hasTable("shields");
  if (exists) {
    return;
  }
  await _knex.schema.createTable("shields", (table) => {
    table.increments("id");
    table.string("pool_id");
    table.integer("token_id");
    table.integer("tick_low");
    table.integer("tick_upper");
    table.timestamp("created_at").defaultTo(_knex.fn.now());
  });
}
