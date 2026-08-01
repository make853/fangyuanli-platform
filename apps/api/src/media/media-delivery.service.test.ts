import assert from "node:assert/strict";
import test from "node:test";
import { MediaDeliveryService } from "./media-delivery.service.js";
import type {
  ObjectReadTicket,
  ObjectStorageAdapter,
  ObjectUploadTicket,
  StoredObject,
  StoredObjectMetadata
} from "./media.storage.js";
import {
  MediaDeliveryError,
  type MediaDeliveryReference
} from "./media.types.js";

class FakeStorage implements ObjectStorageAdapter {
  readKeys: string[] = [];
  fail = false;

  async createReadTicket(input: {
    objectKey: string;
    expiresInSeconds: number;
  }): Promise<ObjectReadTicket> {
    if (this.fail) throw new Error("COS unavailable");
    this.readKeys.push(input.objectKey);
    return {
      url: `https://private.example/${input.objectKey}?signed=1`,
      expiresAt: new Date("2026-08-02T01:10:00.000Z")
    };
  }

  async createUploadTicket(): Promise<ObjectUploadTicket> {
    throw new Error("unused");
  }

  async headObject(): Promise<StoredObjectMetadata | null> {
    throw new Error("unused");
  }

  async getObject(): Promise<StoredObject> {
    throw new Error("unused");
  }

  async putObject(): Promise<StoredObjectMetadata> {
    throw new Error("unused");
  }

  async deleteObject(): Promise<void> {}
}

function reference(
  overrides: Partial<MediaDeliveryReference> = {}
): MediaDeliveryReference {
  return {
    mediaId: "019f0000-0000-7000-8000-00000000000a",
    mediaType: "image",
    status: "ready",
    displayObjectKey: "processed/user/media/avatar-512.webp",
    thumbnailObjectKey: "processed/user/media/avatar-128.webp",
    coverObjectKey: null,
    width: 512,
    height: 512,
    durationMs: null,
    ...overrides
  };
}

test("signs only the derived objects and exposes a short expiry", async () => {
  const storage = new FakeStorage();
  const service = new MediaDeliveryService(storage);

  const view = await service.createView(reference());

  assert.deepEqual(storage.readKeys, [
    "processed/user/media/avatar-512.webp",
    "processed/user/media/avatar-128.webp"
  ]);
  assert.match(view.url ?? "", /\?signed=1$/);
  assert.match(view.thumbnailUrl ?? "", /\?signed=1$/);
  assert.equal(view.expiresAt, "2026-08-02T01:10:00.000Z");
});

test("does not issue a read URL before processing is ready", async () => {
  const storage = new FakeStorage();
  const service = new MediaDeliveryService(storage);

  const view = await service.createView(reference({ status: "processing" }));

  assert.equal(view.url, null);
  assert.equal(view.expiresAt, null);
  assert.deepEqual(storage.readKeys, []);
});

test("maps storage signing failures to a stable delivery error", async () => {
  const storage = new FakeStorage();
  storage.fail = true;
  const service = new MediaDeliveryService(storage);

  await assert.rejects(
    service.createView(reference()),
    (error: unknown) =>
      error instanceof MediaDeliveryError &&
      error.code === "MEDIA_DELIVERY_UNAVAILABLE"
  );
});
