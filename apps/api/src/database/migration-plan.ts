import { createHash } from "node:crypto";
import { readFile, readdir } from "node:fs/promises";
import path from "node:path";

const migrationNamePattern = /^\d{4}_[a-z0-9_]+\.sql$/;

export type MigrationFile = {
  name: string;
  checksum: string;
  sql: string;
};

export type AppliedMigration = {
  name: string;
  checksum: string;
};

export async function loadMigrationFiles(
  directory: string
): Promise<MigrationFile[]> {
  const entries = await readdir(directory, { withFileTypes: true });
  const names = entries
    .filter((entry) => entry.isFile() && entry.name.endsWith(".sql"))
    .map((entry) => entry.name)
    .sort();

  for (const name of names) {
    if (!migrationNamePattern.test(name)) {
      throw new Error(`Invalid migration filename: ${name}`);
    }
  }

  return Promise.all(
    names.map(async (name) => {
      const sql = await readFile(path.join(directory, name), "utf8");
      return {
        name,
        checksum: createHash("sha256").update(sql).digest("hex"),
        sql
      };
    })
  );
}

export function pendingMigrations(
  available: MigrationFile[],
  applied: AppliedMigration[]
): MigrationFile[] {
  if (applied.length > available.length) {
    throw new Error("Database contains migrations missing from the repository");
  }

  for (const [index, appliedMigration] of applied.entries()) {
    const repositoryMigration = available[index];

    if (!repositoryMigration || repositoryMigration.name !== appliedMigration.name) {
      throw new Error(
        `Migration history diverged at ${appliedMigration.name}`
      );
    }

    if (repositoryMigration.checksum !== appliedMigration.checksum) {
      throw new Error(
        `Applied migration was modified: ${appliedMigration.name}`
      );
    }
  }

  return available.slice(applied.length);
}
