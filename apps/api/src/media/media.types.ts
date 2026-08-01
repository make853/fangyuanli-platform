export type MediaPurpose =
  | "avatar"
  | "background"
  | "chat"
  | "post"
  | "report"
  | "placeClaim";

export type MediaType = "image" | "voice" | "video" | "sticker";
export type MediaStatus =
  | "uploading"
  | "processing"
  | "ready"
  | "failed"
  | "expired";

export type MediaUploadSpec = {
  purpose: MediaPurpose;
  mediaType: MediaType;
  fileName: string;
  contentType: string;
  bytes: number;
  sha256: string;
  durationMs: number | null;
  width: number | null;
  height: number | null;
};

export type MediaUploadSession = MediaUploadSpec & {
  uploadId: string;
  ownerUserId: string;
  objectKey: string;
  status: "pending" | "processing" | "completed" | "failed" | "expired";
  createRequestHash: string;
  completeIdempotencyHash: string | null;
  completeRequestHash: string | null;
  mediaAssetId: string | null;
  etag: string | null;
  expiresAt: Date;
};

export type MediaUploadTicket = {
  uploadId: string;
  method: "PUT";
  uploadUrl: string;
  headers: Record<string, string>;
  expiresAt: string;
};

export type MediaView = {
  mediaId: string;
  mediaType: MediaType;
  status: MediaStatus;
  url: string | null;
  thumbnailUrl: string | null;
  coverUrl: string | null;
  width: number | null;
  height: number | null;
  durationMs: number | null;
  expiresAt: string | null;
};

export class MediaDomainError extends Error {
  constructor(
    public readonly code: string,
    message: string,
    public readonly status: number
  ) {
    super(message);
  }
}
