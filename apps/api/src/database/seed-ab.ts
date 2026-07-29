import { readFile } from "node:fs/promises";
import path from "node:path";
import pg from "pg";
import {
  loadRepositoryEnvironment,
  requireDatabaseUrl
} from "./environment.js";
import { assertAbSeedAllowed } from "./seed-guard.js";

const { Client } = pg;

loadRepositoryEnvironment();
assertAbSeedAllowed(process.env);

const seedFile = path.resolve(
  process.cwd(),
  "../../database/seeds/staging/0001_ab_users.sql"
);
const sql = await readFile(seedFile, "utf8");
const client = new Client({
  application_name: "fangyuanli-ab-seed",
  connectionString: requireDatabaseUrl(process.env)
});

await client.connect();

try {
  await client.query("BEGIN");
  await client.query(sql);
  await client.query("COMMIT");
  console.log("Staging A/B test accounts are ready.");
} catch (error) {
  await client.query("ROLLBACK");
  throw error;
} finally {
  await client.end();
}
