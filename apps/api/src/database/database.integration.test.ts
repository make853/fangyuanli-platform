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
      const namingKindColumn = await database.query<{
        data_type: string;
        is_nullable: "YES" | "NO";
      }>(
        `SELECT data_type, is_nullable
           FROM information_schema.columns
          WHERE table_schema = 'public'
            AND table_name = 'plaza_grids'
            AND column_name = 'naming_kind'`
      );
      assert.deepEqual(namingKindColumn.rows, [
        { data_type: "character varying", is_nullable: "YES" }
      ]);
      const namingAuditColumns = await database.query<{
        column_name: string;
        data_type: string;
        is_nullable: "YES" | "NO";
      }>(
        `SELECT column_name, data_type, is_nullable
           FROM information_schema.columns
          WHERE table_schema = 'public'
            AND table_name = 'plaza_grids'
            AND column_name IN (
              'naming_provider',
              'naming_provider_place_id',
              'naming_longitude_gcj02',
              'naming_latitude_gcj02'
            )
          ORDER BY column_name`
      );
      assert.deepEqual(namingAuditColumns.rows, [
        {
          column_name: "naming_latitude_gcj02",
          data_type: "numeric",
          is_nullable: "YES"
        },
        {
          column_name: "naming_longitude_gcj02",
          data_type: "numeric",
          is_nullable: "YES"
        },
        {
          column_name: "naming_provider",
          data_type: "character varying",
          is_nullable: "YES"
        },
        {
          column_name: "naming_provider_place_id",
          data_type: "character varying",
          is_nullable: "YES"
        }
      ]);
      const historyEntryColumns = await database.query<{
        column_name: string;
        is_nullable: "YES" | "NO";
      }>(
        `SELECT column_name, is_nullable
           FROM information_schema.columns
          WHERE table_schema = 'public'
            AND table_name = 'user_chat_history_entries'
            AND column_name IN (
              'user_id', 'conversation_id', 'last_entered_at', 'entry_count'
            )
          ORDER BY column_name`
      );
      assert.deepEqual(historyEntryColumns.rows, [
        { column_name: "conversation_id", is_nullable: "NO" },
        { column_name: "entry_count", is_nullable: "NO" },
        { column_name: "last_entered_at", is_nullable: "NO" },
        { column_name: "user_id", is_nullable: "NO" }
      ]);
    } finally {
      await database.onApplicationShutdown();
    }
  }
);
