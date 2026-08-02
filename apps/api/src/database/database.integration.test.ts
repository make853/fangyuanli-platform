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

test(
  "migrations activate the two-kilometre grid and version automatic plaza names",
  { skip: process.env.RUN_DATABASE_INTEGRATION_TESTS !== "true" },
  async () => {
    const pool = new Pool({
      application_name: "fangyuanli-plaza-grid-integration-test",
      connectionString: requireDatabaseUrl(process.env),
      max: 1
    });
    const database = new DatabaseService(pool);

    try {
      const result = await database.query<{
        version: number;
        side_length_meters: number;
        status: "active" | "retired";
      }>(
        `SELECT version, side_length_meters, status
           FROM plaza_grid_versions
          ORDER BY version`
      );

      assert.deepEqual(result.rows, [
        { version: 1, side_length_meters: 500, status: "retired" },
        { version: 2, side_length_meters: 1000, status: "retired" },
        { version: 3, side_length_meters: 2000, status: "active" }
      ]);
      const namingColumn = await database.query<{
        column_default: string;
        is_nullable: "YES" | "NO";
      }>(
        `SELECT column_default, is_nullable
           FROM information_schema.columns
          WHERE table_schema = 'public'
            AND table_name = 'plaza_grids'
            AND column_name = 'naming_policy_version'`
      );
      assert.equal(namingColumn.rows[0]?.is_nullable, "NO");
      assert.match(namingColumn.rows[0]?.column_default ?? "", /1/);
    } finally {
      await database.onApplicationShutdown();
    }
  }
);
