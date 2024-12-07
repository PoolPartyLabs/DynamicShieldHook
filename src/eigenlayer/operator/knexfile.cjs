module.exports = {
  client: 'pg', 
  connection: {
    connectionString: process.env.DB_URI,
    ssl: process.env.NEXT_NO_SSL?.toString() === "true" ? undefined : { rejectUnauthorized: false }
  },
  pool: {
    min: 2,
    max: 10
  }
};
