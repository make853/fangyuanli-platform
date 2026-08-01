import assert from "node:assert/strict";
import test from "node:test";
import { Pool } from "pg";
import { DatabaseService } from "./database.service.js";
import { requireDatabaseUrl } from "./environment.js";

test(
  "shared database service commits and rolls back against PostgreSQL",
  { skip: process.env.RUN_DATABASE_INTEGRATION_TESTS !== "true" },
  async () => {
    const pool = new Pool({
      application_name: "fangyuanli-database-integration-test",
      connectionString: requireDatabaseUrl(process.env),
      max: 1
    });
    const database = new DatabaseService(pool);

    try {
      await database.transaction(async (transaction) => {
        await transaction.query(
          "CREATE TEMP TABLE database_service_test (value text NOT NULL)"
        );
        await transaction.query(
          "INSERT INTO database_service_test (value) VALUES ($1)",
          ["committed"]
        );
      });

      await assert.rejects(
        database.transaction(async () => {
          await database.query(
            "INSERT INTO database_service_test (value) VALUES ($1)",
            ["rolled-back"]
          );
          throw new Error("force rollback");
        }),
        /force rollback/
      );

      const result = await database.query<{ value: string }>(
        "SELECT value FROM database_service_test ORDER BY value"
      );
      assert.deepEqual(result.rows, [{ value: "committed" }]);
    } finally {
      await database.onApplicationShutdown();
    }
  }
);
