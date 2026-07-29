import assert from "node:assert/strict";
import test from "node:test";
import { createApp } from "./bootstrap.js";

test("GET /health returns an operational response", async (t) => {
  process.env.DATABASE_URL ??= "postgresql://test:test@127.0.0.1:5432/test";
  process.env.REALTIME_ENABLED = "false";
  const app = await createApp();
  await app.init();
  t.after(async () => app.close());

  const response = await app.getHttpAdapter().getInstance().inject({
    method: "GET",
    url: "/health"
  });

  assert.equal(response.statusCode, 200);
  assert.deepEqual(response.json(), {
    service: "fangyuanli-api",
    status: "ok",
    version: "0.1.0"
  });
});
