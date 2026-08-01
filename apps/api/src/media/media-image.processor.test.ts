import assert from "node:assert/strict";
import test from "node:test";
import sharp from "sharp";
import { MediaImageProcessor } from "./media-image.processor.js";
import type {
  ObjectReadTicket,
  ObjectStorageAdapter,
  ObjectUploadTicket,
  StoredObject,
  StoredObjectMetadata,
  StoredObjectWriteResult
} from "./media.storage.js";
import {
  MediaProcessingError,
  type MediaProcessingJob
} from "./media-processing.types.js";

class FakeStorage implements ObjectStorageAdapter {
  source: Buffer = Buffer.alloc(0);
  readError: Error | null = null;
  written = new Map<string, Buffer>();

  async getObject(): Promise<StoredObject> {
    if (this.readError) throw this.readError;
    return {
      body: this.source,
      bytes: this.source.byteLength,
      etag: "source-etag",
      contentType: "image/jpeg"
    };
  }

  async putObject(input: {
    objectKey: string;
    contentType: string;
    body: Buffer;
  }): Promise<StoredObjectWriteResult> {
    assert.equal(input.contentType, "image/webp");
    this.written.set(input.objectKey, input.body);
    return { bytes: input.body.byteLength, etag: "output-etag" };
  }

  async createUploadTicket(): Promise<ObjectUploadTicket> {
    throw new Error("unused");
  }

  async createReadTicket(): Promise<ObjectReadTicket> {
    throw new Error("unused");
  }

  async headObject(): Promise<StoredObjectMetadata | null> {
    throw new Error("unused");
  }

  async deleteObject(): Promise<void> {}
}

test("creates deterministic metadata-free avatar variants", async () => {
  const storage = new FakeStorage();
  storage.source = await sharp({
    create: {
      width: 2400,
      height: 1800,
      channels: 3,
      background: { r: 22, g: 122, b: 91 }
    }
  })
    .jpeg()
    .toBuffer();
  const result = await new MediaImageProcessor(storage).process(job());

  assert.equal(
    result.displayObjectKey,
    `processed/${ownerUserId}/${mediaId}/avatar-512.webp`
  );
  assert.equal(
    result.thumbnailObjectKey,
    `processed/${ownerUserId}/${mediaId}/avatar-128.webp`
  );
  assert.equal(result.width, 512);
  assert.equal(result.height, 512);
  assert.equal(storage.written.size, 2);

  const display = await sharp(
    storage.written.get(result.displayObjectKey)
  ).metadata();
  const thumbnail = await sharp(
    storage.written.get(result.thumbnailObjectKey)
  ).metadata();
  assert.equal(display.format, "webp");
  assert.equal(display.width, 512);
  assert.equal(display.height, 512);
  assert.equal(display.exif, undefined);
  assert.equal(thumbnail.width, 128);
  assert.equal(thumbnail.height, 128);
});

test("classifies invalid image bytes as a permanent failure", async () => {
  const storage = new FakeStorage();
  storage.source = Buffer.from("not-an-image");

  await assert.rejects(
    new MediaImageProcessor(storage).process(job()),
    (error: unknown) =>
      error instanceof MediaProcessingError &&
      error.code === "MEDIA_IMAGE_INVALID" &&
      !error.retryable
  );
});

test("classifies source storage outages as retryable", async () => {
  const storage = new FakeStorage();
  storage.readError = new Error("temporary COS failure");

  await assert.rejects(
    new MediaImageProcessor(storage).process(job()),
    (error: unknown) =>
      error instanceof MediaProcessingError &&
      error.code === "MEDIA_SOURCE_UNAVAILABLE" &&
      error.retryable
  );
});

const ownerUserId = "019f0000-0000-7000-8000-00000000000a";
const mediaId = "019f0000-0000-7000-8000-00000000000b";

function job(): MediaProcessingJob {
  return {
    jobId: "019f0000-0000-7000-8000-00000000000c",
    mediaId,
    ownerUserId,
    purpose: "avatar",
    mediaType: "image",
    sourceObjectKey: "temporary/source.jpg",
    contentType: "image/jpeg",
    bytes: 1024,
    width: 2400,
    height: 1800,
    attemptCount: 1,
    leaseOwner: "worker-1",
    leaseExpiresAt: new Date(Date.now() + 60_000)
  };
}
