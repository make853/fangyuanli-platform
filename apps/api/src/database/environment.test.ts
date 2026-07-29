import assert from "node:assert/strict";
import test from "node:test";
import { requireDatabaseUrl } from "./environment.js";

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
