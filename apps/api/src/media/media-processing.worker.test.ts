import assert from "node:assert/strict";
import test from "node:test";
import type { MediaImageProcessor } from "./media-image.processor.js";
import type { MediaProcessingRepository } from "./media-processing.repository.js";
import { MediaProcessingWorker } from "./media-processing.worker.js";
import {
  MediaProcessingError,
  type MediaProcessingJob,
  type MediaProcessingResult
} from "./media-processing.types.js";

class FakeRepository {
  claimed: MediaProcessingJob | null = job();
  completed: Array<Record<string, unknown>> = [];
  failed: Array<{
    errorCode: string;
    retryAt: Date | null;
  }> = [];

  async claimNext(): Promise<MediaProcessingJob | null> {
    const claimed = this.claimed;
    this.claimed = null;
    return claimed;
  }

  async complete(input: Record<string, unknown>): Promise<void> {
    this.completed.push(input);
  }

  async fail(input: {
    errorCode: string;
    retryAt: Date | null;
  }): Promise<void> {
    this.failed.push(input);
  }
}

class FakeProcessor {
  error: Error | null = null;

  async process(): Promise<MediaProcessingResult> {
    if (this.error) throw this.error;
    return {
      displayObjectKey: "processed/display.webp",
      thumbnailObjectKey: "processed/thumbnail.webp",
      width: 512,
      height: 512,
      displayBytes: 1024
    };
  }
}

test("completes a successfully processed job", async () => {
  const { repository, worker } = fixture();

  assert.equal(await worker.runOnce("worker-1"), true);
  assert.equal(repository.completed.length, 1);
  assert.equal(repository.failed.length, 0);
});

test("returns false when no processing job is available", async () => {
  const { repository, worker } = fixture();
  repository.claimed = null;

  assert.equal(await worker.runOnce("worker-1"), false);
  assert.equal(repository.completed.length, 0);
});

test("schedules retryable failures with backoff", async () => {
  const { repository, processor, worker } = fixture();
  processor.error = new MediaProcessingError(
    "MEDIA_SOURCE_UNAVAILABLE",
    "temporary failure",
    true
  );

  await worker.runOnce("worker-1");

  assert.equal(repository.failed[0]?.errorCode, "MEDIA_SOURCE_UNAVAILABLE");
  assert.ok(repository.failed[0]?.retryAt instanceof Date);
});

test("marks permanent failures without another retry", async () => {
  const { repository, processor, worker } = fixture();
  processor.error = new MediaProcessingError(
    "MEDIA_IMAGE_INVALID",
    "invalid image",
    false
  );

  await worker.runOnce("worker-1");

  assert.equal(repository.failed[0]?.errorCode, "MEDIA_IMAGE_INVALID");
  assert.equal(repository.failed[0]?.retryAt, null);
});

test("stops retrying a transient failure after five attempts", async () => {
  const { repository, processor, worker } = fixture();
  repository.claimed = job(5);
  processor.error = new MediaProcessingError(
    "MEDIA_DERIVATIVE_WRITE_FAILED",
    "temporary failure",
    true
  );

  await worker.runOnce("worker-1");

  assert.equal(repository.failed[0]?.retryAt, null);
});

function fixture(): {
  repository: FakeRepository;
  processor: FakeProcessor;
  worker: MediaProcessingWorker;
} {
  const repository = new FakeRepository();
  const processor = new FakeProcessor();
  return {
    repository,
    processor,
    worker: new MediaProcessingWorker(
      repository as unknown as MediaProcessingRepository,
      processor as unknown as MediaImageProcessor
    )
  };
}

function job(attemptCount = 1): MediaProcessingJob {
  return {
    jobId: "019f0000-0000-7000-8000-00000000000c",
    mediaId: "019f0000-0000-7000-8000-00000000000b",
    ownerUserId: "019f0000-0000-7000-8000-00000000000a",
    purpose: "avatar",
    mediaType: "image",
    sourceObjectKey: "temporary/source.jpg",
    contentType: "image/jpeg",
    bytes: 1024,
    width: 800,
    height: 800,
    attemptCount,
    leaseOwner: "worker-1",
    leaseExpiresAt: new Date(Date.now() + 60_000)
  };
}
