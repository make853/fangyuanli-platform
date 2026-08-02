import path from "node:path";

export type PlazaRegionAuditArguments = {
  userId: string | null;
  latest: boolean;
  output: string;
};

export function parsePlazaRegionAuditArguments(
  argv: string[]
): PlazaRegionAuditArguments {
  let userId: string | null = null;
  let latest = false;
  let output = "";
  for (let index = 0; index < argv.length; index += 1) {
    const value = argv[index];
    if (value === "--") {
      continue;
    }
    if (value === "--latest") {
      latest = true;
    } else if (value === "--user-id") {
      userId = argv[++index]?.trim() || null;
    } else if (value === "--output") {
      output = argv[++index]?.trim() || "";
    } else {
      throw new Error(`Unknown or incomplete argument: ${value ?? ""}`);
    }
  }
  if (Number(latest) + Number(Boolean(userId)) !== 1) {
    throw new Error("Choose exactly one of --latest or --user-id <uuid>");
  }
  if (
    userId &&
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu.test(
      userId
    )
  ) {
    throw new Error("--user-id must be a UUID");
  }
  if (!output || path.extname(output).toLowerCase() !== ".svg") {
    throw new Error("--output must point to an .svg file");
  }
  return { userId, latest, output: path.resolve(output) };
}
