import { existsSync } from "node:fs";
import path from "node:path";
import { randomUUID } from "node:crypto";
import { CosObjectStorageAdapter } from "../src/media/media.storage.js";

const environmentFile = path.resolve(process.cwd(), "../../.env");
if (existsSync(environmentFile)) process.loadEnvFile(environmentFile);

const storage = new CosObjectStorageAdapter();
const body = Buffer.from(`fangyuanli-cos-check:${randomUUID()}`, "utf8");
const objectKey = `temporary/diagnostics/${randomUUID()}.txt`;
let uploaded = false;

try {
  const ticket = await storage.createUploadTicket({
    objectKey,
    contentType: "text/plain; charset=utf-8",
    expiresInSeconds: 120
  });
  const upload = await fetch(ticket.url, {
    method: ticket.method,
    headers: ticket.headers,
    body
  });
  if (!upload.ok) {
    throw new Error(`pre-signed PUT failed with HTTP ${upload.status}`);
  }
  const uploadEtag = upload.headers.get("etag")?.replace(/^"|"$/g, "");
  if (!uploadEtag) {
    throw new Error("COS did not return an ETag for the uploaded object");
  }
  uploaded = true;

  const stored = await storage.headObject(objectKey);
  if (
    !stored ||
    stored.bytes !== body.byteLength ||
    stored.etag !== uploadEtag
  ) {
    throw new Error("uploaded object metadata did not match the test payload");
  }

  await storage.deleteObject(objectKey);
  uploaded = false;
  console.log("COS check passed: signed PUT, HEAD and DELETE all succeeded.");
} finally {
  if (uploaded) {
    try {
      await storage.deleteObject(objectKey);
      uploaded = false;
    } catch {
      console.error(`COS cleanup failed for object: ${objectKey}`);
    }
  }
}
