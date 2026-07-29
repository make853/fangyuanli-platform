import assert from "node:assert/strict";
import test from "node:test";
import { resolveListenOptions } from "./runtime-config.js";

test("API listens on loopback port 3000 by default", () => {
  assert.deepEqual(resolveListenOptions({}), {
    host: "127.0.0.1",
    port: 3000
  });
});

test("API accepts an explicit host and port", () => {
  assert.deepEqual(
    resolveListenOptions({ HOST: "0.0.0.0", PORT: "8080" }),
    {
      host: "0.0.0.0",
      port: 8080
    }
  );
});

test("API rejects an invalid port", () => {
  assert.throws(
    () => resolveListenOptions({ PORT: "70000" }),
    /Invalid PORT value/
  );
});
