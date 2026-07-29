import path from "node:path";
import pg from "pg";
import {
  loadRepositoryEnvironment,
  requireDatabaseUrl
} from "./environment.js";
import {
  loadMigrationFiles,
  pendingMigrations,
  type AppliedMigration
} from "./migration-plan.js";

const { Client } = pg;
const migrationLockKey = 740_701_001;

loadRepositoryEnvironment();

const client = new Client({
  application_name: "fangyuanli-migrations",
  connectionString: requireDatabaseUrl(process.env)
});

await client.connect();

try {
  await client.query("SELECT pg_advisory_lock($1)", [migrationLockKey]);
  await client.query(`
    CREATE TABLE IF NOT EXISTS schema_migrations (
      name text PRIMARY KEY,
      checksum char(64) NOT NULL,
      applied_at timestamptz NOT NULL DEFAULT now()
    )
  `);

  const migrationDirectory = path.resolve(
    process.cwd(),
    "../../database/migrations"
  );
  const available = await loadMigrationFiles(migrationDirectory);
  const result = await client.query<AppliedMigration>(
    "SELECT name, checksum FROM schema_migrations ORDER BY name"
  );
  const pending = pendingMigrations(available, result.rows);

  if (pending.length === 0) {
    console.log("Database schema is up to date.");
  }

  for (const migration of pending) {
    console.log(`Applying ${migration.name}`);
    await client.query("BEGIN");

    try {
      await client.query(migration.sql);
      await client.query(
        "INSERT INTO schema_migrations (name, checksum) VALUES ($1, $2)",
        [migration.name, migration.checksum]
      );
      await client.query("COMMIT");
    } catch (error) {
      await client.query("ROLLBACK");
      throw error;
    }
  }
} finally {
  await client.query("SELECT pg_advisory_unlock($1)", [migrationLockKey]);
  await client.end();
}
