export const PRIVATE_KEY = (process.env.PRIV_KEY_ORACLE ||
  "0x0") as `0x${string}`;
export const CONTRACT = (process.env.CONTRACT || "0x0") as `0x${string}`;
export const DB_URI = process.env.DB_URI || "";
export const RPC_PROVIDER = process.env.RPC_PROVIDER || "";
