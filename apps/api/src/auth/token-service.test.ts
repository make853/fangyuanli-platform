import assert from "node:assert/strict";
import test from "node:test";
import { TokenService } from "./token-service.js";

const environment: NodeJS.ProcessEnv = {
  AUTH_ACCESS_TOKEN_SECRET: "access-secret-for-tests-only-123456789",
  AUTH_REFRESH_TOKEN_SECRET: "refresh-secret-for-tests-only-12345678"
};

test("issues and verifies access claims", async () => {
  const service = new TokenService(environment);
  const claims = {
    userId: "5c930f51-2674-4860-bd5d-d8730c08d2de",
    sessionId: "284f7f03-2024-4f65-86ae-dfcbaf018b83",
    deviceId: "4f34f896-ff79-41f0-a0ed-ab8c550d6197",
    tokenVersion: 2
  };
  const issued = await service.issueTokens(claims, "refresh-token");
  assert.deepEqual(await service.verifyAccessToken(issued.accessToken), claims);
});

test("creates deterministic login refresh tokens but random rotation tokens", () => {
  const service = new TokenService(environment);
  const first = service.createDeterministicRefreshToken("verification", "request");
  const retry = service.createDeterministicRefreshToken("verification", "request");
  assert.equal(first, retry);
  assert.notEqual(service.createRefreshToken(), service.createRefreshToken());
  assert.equal(service.hashRefreshToken(first).length, 64);
});
