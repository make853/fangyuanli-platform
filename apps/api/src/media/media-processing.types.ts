import type { MediaPurpose, MediaType } from "./media.types.js";

export type MediaProcessingJobStatus =
  | "pending"
  | "processing"
  | "retry"
  | "completed"
  | "failed";

export type MediaProcessingJob = {
  jobId: string;
  mediaId: string;
  ownerUserId: string;
  purpose: MediaPurpose;
  mediaType: MediaType;
  sourceObjectKey: string;
  contentType: string;
  bytes: number;
  width: number | null;
  height: number | null;
  attemptCount: number;
  leaseOwner: string;
  leaseExpiresAt: Date;
};

export type MediaProcessingResult = {
  displayObjectKey: string;
  thumbnailObjectKey: string;
  width: number;
  height: number;
  displayBytes: number;
};

export class MediaProcessingError extends Error {
  constructor(
    public readonly code: string,
    message: string,
    public readonly retryable: boolean
  ) {
    super(message);
  }
}

export class MediaProcessingLeaseLost extends Error {
  constructor() {
    super("Media processing lease is no longer owned by this worker");
  }
}
