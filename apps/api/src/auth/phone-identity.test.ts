import assert from "node:assert/strict";
import test from "node:test";
import { AuthDomainError } from "./auth.types.js";
import { PhoneIdentityService } from "./phone-identity.js";

const encryptionKey = Buffer.alloc(32, 7).toString("base64");

function environment(overrides: NodeJS.ProcessEnv = {}): NodeJS.ProcessEnv {
  return {
    PHONE_HASH_KEY: "phone-hash-key-for-tests-only-12345",
    PHONE_ENCRYPTION_KEY: encryptionKey,
    SMS_CODE_HASH_KEY: "sms-code-key-for-tests-only-123456",
    AUTH_REFRESH_TOKEN_SECRET: "refresh-secret-for-tests-only-123456",
    ...overrides
  };
}

test("accepts a mainland China mobile number without exposing it in the hash", () => {
  const service = new PhoneIdentityService(environment());
  const identity = service.create("+86", "13800138000");

  assert.equal(identity.countryCode, "+86");
  assert.equal(identity.lastFour, "8000");
  assert.equal(identity.hash.length, 64);
  assert.equal(identity.hash.includes("13800138000"), false);
  assert.match(identity.ciphertext, /^v1\./);
});

test("rejects email-only and invalid mobile identities", () => {
  const service = new PhoneIdentityService(environment());
  assert.throws(
    () => service.create("+86", "user@example.com"),
    (error: unknown) =>
      error instanceof AuthDomainError && error.code === "AUTH_PHONE_INVALID"
  );
});

test("allows configured A/B aliases only in explicitly enabled staging", () => {
  const staging = new PhoneIdentityService(
    environment({
      NODE_ENV: "staging",
      ALLOW_STAGING_SMS: "true",
      STAGING_TEST_PHONE_A: "test-a"
    })
  );
  assert.equal(
    staging.create("+86", "test-a").hash,
    "staging-test-only:phone-hash-a"
  );

  const production = new PhoneIdentityService(
    environment({
      NODE_ENV: "production",
      ALLOW_STAGING_SMS: "true",
      STAGING_TEST_PHONE_A: "test-a"
    })
  );
  assert.throws(() => production.create("+86", "test-a"), AuthDomainError);
});
