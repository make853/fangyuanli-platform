import { Injectable } from "@nestjs/common";
import { setTimeout as delay } from "node:timers/promises";
import { MediaImageProcessor } from "./media-image.processor.js";
import { MediaProcessingRepository } from "./media-processing.repository.js";
import { MediaProcessingError } from "./media-processing.types.js";

const DEFAULT_LEASE_MS = 2 * 60 * 1000;
const DEFAULT_POLL_MS = 1_000;
const MAX_ATTEMPTS = 5;

@Injectable()
export class MediaProcessingWorker {
  constructor(
    private readonly repository: MediaProcessingRepository,
    private readonly processor: MediaImageProcessor
  ) {}

  async run(
    workerId: string,
    signal: AbortSignal,
    options: { pollMs?: number; leaseMs?: number } = {}
  ): Promise<void> {
    const pollMs = options.pollMs ?? DEFAULT_POLL_MS;
    const leaseMs = options.leaseMs ?? DEFAULT_LEASE_MS;
    while (!signal.aborted) {
      try {
        const processed = await this.runOnce(workerId, leaseMs);
        if (processed) continue;
      } catch (error) {
        console.error("media_worker_iteration_failed", this.errorCode(error));
      }
      try {
        await delay(pollMs, undefined, { signal });
      } catch {
        if (!signal.aborted) throw new Error("Media worker delay failed");
      }
    }
  }

  async runOnce(
    workerId: string,
    leaseDurationMs = DEFAULT_LEASE_MS
  ): Promise<boolean> {
    const job = await this.repository.claimNext({
      workerId,
      now: new Date(),
      leaseDurationMs
    });
    if (!job) return false;

    try {
      const result = await this.processor.process(job);
      await this.repository.complete({
        jobId: job.jobId,
        workerId,
        result,
        now: new Date()
      });
    } catch (error) {
      const processingError = this.processingError(error);
      const retryAt =
        processingError.retryable && job.attemptCount < MAX_ATTEMPTS
          ? new Date(Date.now() + this.retryDelayMs(job.attemptCount))
          : null;
      await this.repository.fail({
        jobId: job.jobId,
        workerId,
        errorCode: processingError.code,
        retryAt,
        now: new Date()
      });
    }
    return true;
  }

  private retryDelayMs(attemptCount: number): number {
    return Math.min(5 * 60_000, 5_000 * 2 ** Math.max(0, attemptCount - 1));
  }

  private processingError(error: unknown): MediaProcessingError {
    if (error instanceof MediaProcessingError) return error;
    return new MediaProcessingError(
      "MEDIA_PROCESSING_UNEXPECTED",
      "媒体处理暂时失败",
      true
    );
  }

  private errorCode(error: unknown): string {
    if (error instanceof Error && error.name) return error.name;
    return "unknown_error";
  }
}
