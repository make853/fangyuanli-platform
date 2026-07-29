export type ListenOptions = {
  host: string;
  port: number;
};

export function resolveListenOptions(
  environment: NodeJS.ProcessEnv
): ListenOptions {
  const host = environment.HOST?.trim() || "127.0.0.1";
  const rawPort = environment.PORT?.trim() || "3000";
  const port = Number(rawPort);

  if (!Number.isInteger(port) || port < 1 || port > 65_535) {
    throw new Error(`Invalid PORT value: ${rawPort}`);
  }

  return { host, port };
}
