import assert from "node:assert/strict";
import test from "node:test";
import type { RequestHasher } from "../relationships/request-hasher.js";
import type { MediaRepository } from "./media.repository.js";
import { MediaService } from "./media.service.js";
import type {
  ObjectReadTicket,
  ObjectStorageAdapter,
  ObjectUploadTicket,
  StoredObject,
  StoredObjectMetadata
} from "./media.storage.js";
import {
  MediaDomainError,
  type MediaUploadSession,
  type MediaUploadSpec,
  type MediaView
} from "./media.types.js";

const userId = "019f0000-0000-7000-8000-00000000000a";
const sha256 = "a".repeat(64);

function uploadBody(
  overrides: Record<string, unknown> = {}
): Record<string, unknown> {
  return {
    purpose: "avatar",
    mediaType: "image",
    fileName: "avatar.jpg",
    contentType: "image/jpeg",
    bytes: 1024,
    sha256,
    width: 800,
    height: 800,
    ...overrides
  };
}

class FakeHasher {
  hash(value: string): string {
    return `hash:${value}`;
  }
}

class FakeStorage implements ObjectStorageAdapter {
  tickets: Array<{
    objectKey: string;
    contentType: string;
    expiresInSeconds: number;
  }> = [];
  headCalls: string[] = [];
  metadata: StoredObjectMetadata | null = {
    bytes: 1024,
    etag: "etag-1"
  };

  async createUploadTicket(input: {
    objectKey: string;
    contentType: string;
    expiresInSeconds: number;
  }): Promise<ObjectUploadTicket> {
    this.tickets.push(input);
    return {
      method: "PUT",
      url: `https://upload.example/${input.objectKey}`,
      headers: { "Content-Type": input.contentType }
    };
  }

  async headObject(objectKey: string): Promise<StoredObjectMetadata | null> {
    this.headCalls.push(objectKey);
    return this.metadata;
  }

  async getObject(): Promise<StoredObject> {
    throw new Error("unused");
  }

  async putObject(): Promise<StoredObjectMetadata> {
    throw new Error("unused");
  }

  async createReadTicket(): Promise<ObjectReadTicket> {
    throw new Error("unused");
  }

  async deleteObject(): Promise<void> {}
}

class FakeMediaRepository {
  session: MediaUploadSession | null = null;
  media: MediaView | null = null;
  completeCalls = 0;

  async createUpload(input: {
    uploadId: string;
    ownerUserId: string;
    spec: MediaUploadSpec;
    objectKey: string;
    createRequestHash: string;
    expiresAt: Date;
  }): Promise<MediaUploadSession> {
    if (this.session) return this.session;
    this.session = {
      uploadId: input.uploadId,
      ownerUserId: input.ownerUserId,
      ...input.spec,
      objectKey: input.objectKey,
      status: "pending",
      createRequestHash: input.createRequestHash,
      completeIdempotencyHash: null,
      completeRequestHash: null,
      mediaAssetId: null,
      etag: null,
      expiresAt: input.expiresAt
    };
    return this.session;
  }

  async getUpload(): Promise<MediaUploadSession> {
    if (!this.session) throw new Error("Upload session missing");
    return this.session;
  }

  async completeUpload(input: {
    completeIdempotencyHash: string;
    completeRequestHash: string;
    etag: string;
  }): Promise<MediaView> {
    this.completeCalls += 1;
    if (!this.session) throw new Error("Upload session missing");
    if (
      this.session.completeIdempotencyHash &&
      (this.session.completeIdempotencyHash !== input.completeIdempotencyHash ||
        this.session.completeRequestHash !== input.completeRequestHash)
    ) {
      throw new MediaDomainError(
        "IDEMPOTENCY_KEY_REUSED",
        "幂等键已用于其他完成请求",
        409
      );
    }
    this.session.completeIdempotencyHash = input.completeIdempotencyHash;
    this.session.completeRequestHash = input.completeRequestHash;
    this.session.mediaAssetId ??= "019f0000-0000-7000-8000-00000000000f";
    this.session.status = "completed";
    this.media ??= {
      mediaId: this.session.mediaAssetId,
      mediaType: this.session.mediaType,
      status: "processing",
      url: null,
      thumbnailUrl: null,
      coverUrl: null,
      width: this.session.width,
      height: this.session.height,
      durationMs: this.session.durationMs,
      expiresAt: null
    };
    return this.media;
  }

  async getMedia(): Promise<MediaView> {
    if (!this.media) throw new Error("Media missing");
    return this.media;
  }
}

function fixture(): {
  repository: FakeMediaRepository;
  storage: FakeStorage;
  service: MediaService;
} {
  const repository = new FakeMediaRepository();
  const storage = new FakeStorage();
  return {
    repository,
    storage,
    service: new MediaService(
      repository as unknown as MediaRepository,
      storage,
      new FakeHasher() as unknown as RequestHasher
    )
  };
}

test("creates a short-lived direct upload ticket and safely retries it", async () => {
  const { repository, storage, service } = fixture();
  const first = await service.createUpload({
    userId,
    idempotencyKey: "avatar-upload-1",
    body: uploadBody()
  });
  const second = await service.createUpload({
    userId,
    idempotencyKey: "avatar-upload-1",
    body: uploadBody()
  });

  assert.equal(first.uploadId, second.uploadId);
  assert.equal(first.method, "PUT");
  assert.equal(first.headers["Content-Type"], "image/jpeg");
  assert.match(first.uploadUrl, /^https:\/\/upload\.example\//);
  assert.equal(storage.tickets.length, 2);
  assert.equal(repository.session?.purpose, "avatar");
  assert.match(repository.session?.objectKey ?? "", /^temporary\//);
});

test("rejects a reused create idempotency key with different file metadata", async () => {
  const { service } = fixture();
  await service.createUpload({
    userId,
    idempotencyKey: "avatar-upload-2",
    body: uploadBody()
  });

  await assert.rejects(
    service.createUpload({
      userId,
      idempotencyKey: "avatar-upload-2",
      body: uploadBody({ sha256: "b".repeat(64) })
    }),
    (error: unknown) =>
      error instanceof MediaDomainError &&
      error.code === "IDEMPOTENCY_KEY_REUSED" &&
      error.status === 409
  );
});

test("enforces video duration and 1080p limits before issuing credentials", async () => {
  const { service } = fixture();
  await assert.rejects(
    service.createUpload({
      userId,
      idempotencyKey: "video-upload-long",
      body: uploadBody({
        purpose: "post",
        mediaType: "video",
        fileName: "video.mp4",
        contentType: "video/mp4",
        durationMs: 20_001,
        width: 1920,
        height: 1080
      })
    }),
    (error: unknown) =>
      error instanceof MediaDomainError &&
      error.code === "MEDIA_VIDEO_TOO_LONG" &&
      error.status === 413
  );

  await assert.rejects(
    service.createUpload({
      userId,
      idempotencyKey: "video-upload-4k",
      body: uploadBody({
        purpose: "post",
        mediaType: "video",
        fileName: "video.mp4",
        contentType: "video/mp4",
        durationMs: 10_000,
        width: 3840,
        height: 2160
      })
    }),
    (error: unknown) =>
      error instanceof MediaDomainError &&
      error.code === "MEDIA_VIDEO_RESOLUTION_TOO_HIGH"
  );
});

test("does not create media until COS confirms the uploaded object", async () => {
  const { repository, storage, service } = fixture();
  const ticket = await service.createUpload({
    userId,
    idempotencyKey: "avatar-upload-3",
    body: uploadBody()
  });
  storage.metadata = null;

  await assert.rejects(
    service.completeUpload({
      userId,
      uploadId: ticket.uploadId,
      idempotencyKey: "avatar-complete-3",
      body: { etag: "etag-1", bytes: 1024, sha256 }
    }),
    (error: unknown) =>
      error instanceof MediaDomainError &&
      error.code === "MEDIA_UPLOAD_INCOMPLETE"
  );
  assert.equal(repository.completeCalls, 0);
});

test("completion is retry-safe and skips a second COS lookup", async () => {
  const { repository, storage, service } = fixture();
  const ticket = await service.createUpload({
    userId,
    idempotencyKey: "avatar-upload-4",
    body: uploadBody()
  });
  const input = {
    userId,
    uploadId: ticket.uploadId,
    idempotencyKey: "avatar-complete-4",
    body: { etag: '"etag-1"', bytes: 1024, sha256 }
  };

  const first = await service.completeUpload(input);
  const second = await service.completeUpload(input);

  assert.equal(first.mediaId, second.mediaId);
  assert.equal(first.status, "processing");
  assert.equal(storage.headCalls.length, 1);
  assert.equal(repository.completeCalls, 2);
});

test("rejects completion metadata that differs from the upload request", async () => {
  const { service } = fixture();
  const ticket = await service.createUpload({
    userId,
    idempotencyKey: "avatar-upload-5",
    body: uploadBody()
  });

  await assert.rejects(
    service.completeUpload({
      userId,
      uploadId: ticket.uploadId,
      idempotencyKey: "avatar-complete-5",
      body: { etag: "etag-1", bytes: 1023, sha256 }
    }),
    (error: unknown) =>
      error instanceof MediaDomainError &&
      error.code === "MEDIA_UPLOAD_MISMATCH"
  );
});
