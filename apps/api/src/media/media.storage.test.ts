import assert from "node:assert/strict";
import test from "node:test";
import {
  CosObjectStorageAdapter,
  CvmRoleCredentialSource
} from "./media.storage.js";

test("loads renewable COS credentials from a bound CVM role", async () => {
  const expiresAt = Math.floor(Date.now() / 1000) + 1_800;
  let requestedUrl = "";
  const source = new CvmRoleCredentialSource(
    "fangyuanli-staging-media",
    async (input) => {
      requestedUrl = input.toString();
      return Response.json({
        Code: "Success",
        TmpSecretId: "temporary-id",
        TmpSecretKey: "temporary-key",
        Token: "temporary-token",
        ExpiredTime: expiresAt
      });
    }
  );

  const credentials = await source.load();

  assert.match(requestedUrl, /fangyuanli-staging-media$/);
  assert.equal(credentials.TmpSecretId, "temporary-id");
  assert.equal(credentials.SecurityToken, "temporary-token");
  assert.equal(credentials.ExpiredTime, expiresAt);
  assert.equal(credentials.ScopeLimit, false);
});

test("rejects unsafe CVM role names before contacting metadata", () => {
  assert.throws(
    () => new CvmRoleCredentialSource("../unexpected-role"),
    /CVM_ROLE is invalid/
  );
});

test("rejects malformed or nearly expired role credentials", async () => {
  const source = new CvmRoleCredentialSource(
    "fangyuanli-staging-media",
    async () =>
      Response.json({
        Code: "Success",
        TmpSecretId: "temporary-id",
        TmpSecretKey: "temporary-key",
        Token: "temporary-token",
        ExpiredTime: Math.floor(Date.now() / 1000) + 30
      })
  );

  await assert.rejects(
    source.load(),
    /invalid or expiring credentials/
  );
});

test("waits for CVM role credentials before returning a signed upload URL", async () => {
  const expiresAt = Math.floor(Date.now() / 1000) + 1_800;
  const storage = new CosObjectStorageAdapter({
    environment: {
      TENCENT_COS_BUCKET: "fangyuanli-staging-1234567890",
      TENCENT_COS_REGION: "ap-shanghai",
      TENCENT_COS_CVM_ROLE: "fangyuanli-staging-media"
    },
    credentialFetcher: async () =>
      Response.json({
        Code: "Success",
        TmpSecretId: "temporary-id",
        TmpSecretKey: "temporary-key",
        Token: "temporary-token",
        ExpiredTime: expiresAt
      })
  });

  const ticket = await storage.createUploadTicket({
    objectKey: "temporary/user-1/upload-1/example.jpg",
    contentType: "image/jpeg",
    expiresInSeconds: 120
  });

  const url = new URL(ticket.url);
  assert.equal(url.protocol, "https:");
  assert.match(url.hostname, /^fangyuanli-staging-1234567890\.cos\./);
  assert.match(url.search, /q-signature=/);
  assert.equal(url.searchParams.get("x-cos-security-token"), "temporary-token");
  assert.deepEqual(ticket.headers, { "Content-Type": "image/jpeg" });
});

test("creates a short-lived signed GET URL without making the bucket public", async () => {
  const expiresAt = Math.floor(Date.now() / 1000) + 1_800;
  const storage = new CosObjectStorageAdapter({
    environment: {
      TENCENT_COS_BUCKET: "fangyuanli-staging-1234567890",
      TENCENT_COS_REGION: "ap-shanghai",
      TENCENT_COS_CVM_ROLE: "fangyuanli-staging-media"
    },
    credentialFetcher: async () =>
      Response.json({
        Code: "Success",
        TmpSecretId: "temporary-id",
        TmpSecretKey: "temporary-key",
        Token: "temporary-token",
        ExpiredTime: expiresAt
      })
  });

  const ticket = await storage.createReadTicket({
    objectKey: "processed/user-1/media-1/avatar-128.webp",
    expiresInSeconds: 600
  });

  const url = new URL(ticket.url);
  assert.equal(url.protocol, "https:");
  assert.match(url.search, /q-signature=/);
  assert.equal(url.searchParams.get("x-cos-security-token"), "temporary-token");
  assert.ok(ticket.expiresAt.getTime() > Date.now());
});
