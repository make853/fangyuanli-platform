export function assertAbSeedAllowed(
  environment: NodeJS.ProcessEnv
): void {
  if (environment.NODE_ENV === "production") {
    throw new Error("A/B test seed is forbidden in production");
  }

  if (environment.ALLOW_TEST_SEED !== "true") {
    throw new Error("Set ALLOW_TEST_SEED=true to load A/B test accounts");
  }
}
