import assert from "node:assert/strict";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import {
  loadMigrationFiles,
  pendingMigrations
} from "./migration-plan.js";

test("loads migrations in filename order and calculates checksums", async (t) => {
  const directory = await mkdtemp(path.join(os.tmpdir(), "fangyuanli-migrations-"));
  t.after(() => rm(directory, { force: true, recursive: true }));

  await writeFile(path.join(directory, "0002_second.sql"), "SELECT 2;\n");
  await writeFile(path.join(directory, "0001_first.sql"), "SELECT 1;\n");

  const migrations = await loadMigrationFiles(directory);

  assert.deepEqual(
    migrations.map(({ name }) => name),
    ["0001_first.sql", "0002_second.sql"]
  );
  assert.match(migrations[0]?.checksum ?? "", /^[a-f0-9]{64}$/);
});

test("rejects a migration filename that cannot be ordered safely", async (t) => {
  const directory = await mkdtemp(path.join(os.tmpdir(), "fangyuanli-migrations-"));
  t.after(() => rm(directory, { force: true, recursive: true }));

  await writeFile(path.join(directory, "initial.sql"), "SELECT 1;\n");

  await assert.rejects(
    loadMigrationFiles(directory),
    /Invalid migration filename/
  );
});

test("returns only the unapplied suffix", () => {
  const available = [
    { name: "0001_first.sql", checksum: "a", sql: "SELECT 1;" },
    { name: "0002_second.sql", checksum: "b", sql: "SELECT 2;" }
  ];

  assert.deepEqual(
    pendingMigrations(available, [
      { name: "0001_first.sql", checksum: "a" }
    ]),
    [available[1]]
  );
});

test("rejects changed or divergent applied migrations", () => {
  const available = [
    { name: "0001_first.sql", checksum: "a", sql: "SELECT 1;" }
  ];

  assert.throws(
    () =>
      pendingMigrations(available, [
        { name: "0001_first.sql", checksum: "changed" }
      ]),
    /Applied migration was modified/
  );

  assert.throws(
    () =>
      pendingMigrations(available, [
        { name: "0002_other.sql", checksum: "a" }
      ]),
    /Migration history diverged/
  );
});
