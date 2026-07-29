import { existsSync } from "node:fs";
import path from "node:path";

export function loadRepositoryEnvironment(): void {
  const environmentFile = path.resolve(process.cwd(), "../../.env");

  if (existsSync(environmentFile)) {
    process.loadEnvFile(environmentFile);
  }
}

export function requireDatabaseUrl(
  environment: NodeJS.ProcessEnv
): string {
  const databaseUrl = environment.DATABASE_URL?.trim();

  if (!databaseUrl) {
    throw new Error("DATABASE_URL is required");
  }

  return databaseUrl;
}
