import assert from "node:assert/strict";
import test from "node:test";
import { assertAbSeedAllowed } from "./seed-guard.js";

test("allows the A/B seed only when explicitly enabled outside production", () => {
  assert.doesNotThrow(() =>
    assertAbSeedAllowed({
      ALLOW_TEST_SEED: "true",
      NODE_ENV: "staging"
    })
  );

  assert.throws(
    () =>
      assertAbSeedAllowed({
        ALLOW_TEST_SEED: "true",
        NODE_ENV: "production"
      }),
    /forbidden in production/
  );

  assert.throws(
    () => assertAbSeedAllowed({ NODE_ENV: "staging" }),
    /ALLOW_TEST_SEED=true/
  );
});
