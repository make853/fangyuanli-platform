import assert from "node:assert/strict";
import test from "node:test";
import {
  requireDatabaseUrl,
  resolveDatabasePoolMax
} from "./environment.js";

test("requires a non-empty database URL", () => {
  assert.throws(() => requireDatabaseUrl({}), /DATABASE_URL is required/);
  assert.throws(
    () => requireDatabaseUrl({ DATABASE_URL: "  " }),
    /DATABASE_URL is required/
  );
});

test("returns a configured database URL", () => {
  assert.equal(
    requireDatabaseUrl({
      DATABASE_URL: "postgresql://user:password@localhost/database"
    }),
    "postgresql://user:password@localhost/database"
  );
});

test("uses a bounded shared database pool size", () => {
  assert.equal(resolveDatabasePoolMax({}), 20);
  assert.equal(resolveDatabasePoolMax({ DATABASE_POOL_MAX: "8" }), 8);
  assert.throws(
    () => resolveDatabasePoolMax({ DATABASE_POOL_MAX: "0" }),
    /Invalid DATABASE_POOL_MAX/
  );
  assert.throws(
    () => resolveDatabasePoolMax({ DATABASE_POOL_MAX: "101" }),
    /Invalid DATABASE_POOL_MAX/
  );
  assert.throws(
    () => resolveDatabasePoolMax({ DATABASE_POOL_MAX: "many" }),
    /Invalid DATABASE_POOL_MAX/
  );
});
