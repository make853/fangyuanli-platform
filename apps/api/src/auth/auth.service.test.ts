import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";
import type { AuthRepository, SessionResult } from "./auth.repository.js";
import { AuthService } from "./auth.service.js";
import { PhoneIdentityService } from "./phone-identity.js";
import { TokenService } from "./token-service.js";

function configureEnvironment(): void {
  process.env.NODE_ENV = "staging";
  process.env.ALLOW_STAGING_SMS = "true";
  process.env.STAGING_TEST_PHONE_A = "test-a";
  process.env.STAGING_SMS_TEST_CODE = "246810";
  process.env.PHONE_HASH_KEY = "phone-hash-key-for-tests-only-12345";
  process.env.PHONE_ENCRYPTION_KEY = Buffer.alloc(32, 5).toString("base64");
  process.env.SMS_CODE_HASH_KEY = "sms-code-key-for-tests-only-123456";
  process.env.AUTH_ACCESS_TOKEN_SECRET = "access-secret-for-tests-only-123456789";
  process.env.AUTH_REFRESH_TOKEN_SECRET = "refresh-secret-for-tests-only-12345678";
}

test("staging login creates a verification and preserves verify idempotency", async () => {
  configureEnvironment();
  let expectedCodeHash = "";
  let verifyInput: Record<string, unknown> | undefined;
  const session: SessionResult = {
    userId: randomUUID(),
    sessionId: randomUUID(),
    deviceId: randomUUID(),
    tokenVersion: 1,
    isNewUser: false
  };
  const repository = {
    async findLatestVerification() {
      return null;
    },
    async createVerification(
      _identity: unknown,
      codeHash: string,
      now: Date,
      id: string
    ) {
      expectedCodeHash = codeHash;
      return {
        id,
        expiresAt: new Date(now.getTime() + 300_000),
        resendAfter: new Date(now.getTime() + 60_000)
      };
    },
    async verifyAndCreateSession(input: Record<string, unknown>) {
      verifyInput = input;
      return session;
    }
  } as unknown as AuthRepository;
  const service = new AuthService(
    repository,
    new PhoneIdentityService(),
    new TokenService()
  );

  const sent = await service.sendSms({
    countryCode: "+86",
    phoneNumber: "test-a",
    purpose: "login"
  });
  const verified = await service.verifySms({
    verificationId: sent.verificationId,
    code: "246810",
    device: { platform: "ios", deviceName: "iPhone" },
    idempotencyKey: "login-attempt-1"
  });

  assert.equal(verifyInput?.codeHash, expectedCodeHash);
  assert.equal(verifyInput?.verificationId, sent.verificationId);
  assert.equal(verified.userId, session.userId);
  assert.equal(verified.deviceId, session.deviceId);
  assert.ok(verified.accessToken);
  assert.ok(verified.refreshToken);
});

test("rejects an email identity before touching the repository", async () => {
  configureEnvironment();
  let repositoryCalled = false;
  const repository = {
    async findLatestVerification() {
      repositoryCalled = true;
      return null;
    }
  } as unknown as AuthRepository;
  const service = new AuthService(
    repository,
    new PhoneIdentityService(),
    new TokenService()
  );

  await assert.rejects(
    service.sendSms({
      countryCode: "+86",
      phoneNumber: "name@example.com",
      purpose: "login"
    }),
    /中国大陆手机号码/
  );
  assert.equal(repositoryCalled, false);
});
