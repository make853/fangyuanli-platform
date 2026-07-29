import assert from "node:assert/strict";
import test from "node:test";
import type { ExecutionContext } from "@nestjs/common";
import { AccessTokenGuard } from "./access-token.guard.js";
import type { AuthRepository } from "./auth.repository.js";
import type { TokenService } from "./token-service.js";

const claims = {
  userId: "11111111-1111-4111-8111-111111111111",
  sessionId: "22222222-2222-4222-8222-222222222222",
  deviceId: "33333333-3333-4333-8333-333333333333",
  tokenVersion: 1
};

function context(request: Record<string, unknown>): ExecutionContext {
  return {
    switchToHttp: () => ({
      getRequest: () => request
    })
  } as unknown as ExecutionContext;
}

test("accepts only a token backed by an active server session", async () => {
  const tokens = {
    async verifyAccessToken() {
      return claims;
    }
  } as unknown as TokenService;
  const repository = {
    async isSessionActive() {
      return true;
    }
  } as unknown as AuthRepository;
  const request = { headers: { authorization: "Bearer valid" } };
  const guard = new AccessTokenGuard(tokens, repository);

  assert.equal(await guard.canActivate(context(request)), true);
  assert.deepEqual((request as { auth?: unknown }).auth, claims);
});

test("rejects a signed token after its server session is revoked", async () => {
  const tokens = {
    async verifyAccessToken() {
      return claims;
    }
  } as unknown as TokenService;
  const repository = {
    async isSessionActive() {
      return false;
    }
  } as unknown as AuthRepository;
  const guard = new AccessTokenGuard(tokens, repository);

  await assert.rejects(
    guard.canActivate(context({ headers: { authorization: "Bearer old" } })),
    (error: unknown) => {
      const response = (
        error as { getResponse?: () => { error?: { code?: string } } }
      ).getResponse?.();
      return response?.error?.code === "AUTH_REQUIRED";
    }
  );
});
