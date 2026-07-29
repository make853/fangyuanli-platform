import { Injectable } from "@nestjs/common";
import { randomUUID } from "node:crypto";
import { RequestHasher } from "../relationships/request-hasher.js";
import { MediaRepository } from "./media.repository.js";
import { ObjectStorageAdapter } from "./media.storage.js";
import {
  MediaDomainError,
  type MediaPurpose,
  type MediaType,
  type MediaUploadSpec,
  type MediaUploadTicket,
  type MediaView
} from "./media.types.js";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SHA256_PATTERN = /^[0-9a-f]{64}$/i;
const UPLOAD_TTL_SECONDS = 15 * 60;
const PURPOSES = new Set<MediaPurpose>([
  "avatar",
  "background",
  "chat",
  "post",
  "report",
  "placeClaim"
]);
const MEDIA_TYPES = new Set<MediaType>([
  "image",
  "voice",
  "video",
  "sticker"
]);
const CONTENT_TYPES: Record<MediaType, Set<string>> = {
  image: new Set([
    "image/jpeg",
    "image/png",
    "image/webp",
    "image/heic",
    "image/heif"
  ]),
  voice: new Set([
    "audio/aac",
    "audio/mp4",
    "audio/mpeg",
    "audio/ogg",
    "audio/x-m4a"
  ]),
  video: new Set(["video/mp4", "video/quicktime"]),
  sticker: new Set(["image/gif", "image/png", "image/webp"])
};
const MAX_BYTES: Record<MediaType, number> = {
  image: 20 * 1024 * 1024,
  voice: 10 * 1024 * 1024,
  video: 80 * 1024 * 1024,
  sticker: 5 * 1024 * 1024
};

@Injectable()
export class MediaService {
  constructor(
    private readonly repository: MediaRepository,
    private readonly storage: ObjectStorageAdapter,
    private readonly hasher: RequestHasher
  ) {}

  async createUpload(input: {
    userId: string;
    body: Record<string, unknown>;
    idempotencyKey?: string;
  }): Promise<MediaUploadTicket> {
    const idempotencyKey = this.idempotencyKey(input.idempotencyKey);
    const spec = this.uploadSpec(input.body);
    const requestHash = this.hasher.hash(this.canonicalUpload(spec));
    const uploadId = randomUUID();
    const now = new Date();
    const expiresAt = new Date(now.getTime() + UPLOAD_TTL_SECONDS * 1000);
    const objectKey = this.objectKey(input.userId, uploadId, spec);
    const session = await this.repository.createUpload({
      uploadId,
      ownerUserId: input.userId,
      spec,
      objectKey,
      createIdempotencyHash: this.hasher.hash(idempotencyKey),
      createRequestHash: requestHash,
      expiresAt,
      now
    });

    if (session.createRequestHash !== requestHash) {
      throw new MediaDomainError(
        "IDEMPOTENCY_KEY_REUSED",
        "幂等键已用于其他上传请求",
        409
      );
    }
    if (session.status !== "pending" || session.expiresAt <= now) {
      throw new MediaDomainError(
        "MEDIA_UPLOAD_EXPIRED",
        "上传凭证已经失效，请重新选择文件",
        410
      );
    }

    try {
      const ticket = await this.storage.createUploadTicket({
        objectKey: session.objectKey,
        contentType: session.contentType,
        expiresInSeconds: Math.max(
          1,
          Math.floor((session.expiresAt.getTime() - now.getTime()) / 1000)
        )
      });
      return {
        uploadId: session.uploadId,
        method: ticket.method,
        uploadUrl: ticket.url,
        headers: ticket.headers,
        expiresAt: session.expiresAt.toISOString()
      };
    } catch {
      throw new MediaDomainError(
        "MEDIA_STORAGE_UNAVAILABLE",
        "媒体存储暂时不可用，请稍后重试",
        503
      );
    }
  }

  async completeUpload(input: {
    userId: string;
    uploadId: unknown;
    body: Record<string, unknown>;
    idempotencyKey?: string;
  }): Promise<MediaView> {
    const uploadId = this.uuid(input.uploadId, "MEDIA_UPLOAD_ID_INVALID");
    const idempotencyKey = this.idempotencyKey(input.idempotencyKey);
    const completion = this.completion(input.body);
    const session = await this.repository.getUpload(input.userId, uploadId);
    const now = new Date();
    if (session.expiresAt <= now && !session.mediaAssetId) {
      throw new MediaDomainError(
        "MEDIA_UPLOAD_EXPIRED",
        "上传凭证已经失效，请重新选择文件",
        410
      );
    }
    if (
      completion.bytes !== session.bytes ||
      completion.sha256 !== session.sha256
    ) {
      throw new MediaDomainError(
        "MEDIA_UPLOAD_MISMATCH",
        "上传文件与申请信息不一致",
        422
      );
    }

    const idempotencyHash = this.hasher.hash(idempotencyKey);
    const requestHash = this.hasher.hash(JSON.stringify(completion));
    if (!session.mediaAssetId) {
      let object;
      try {
        object = await this.storage.headObject(session.objectKey);
      } catch {
        throw new MediaDomainError(
          "MEDIA_STORAGE_UNAVAILABLE",
          "媒体存储暂时不可用，请稍后重试",
          503
        );
      }
      if (!object) {
        throw new MediaDomainError(
          "MEDIA_UPLOAD_INCOMPLETE",
          "文件尚未上传完成",
          422
        );
      }
      if (
        object.bytes !== session.bytes ||
        this.normalizeEtag(object.etag) !== completion.etag
      ) {
        throw new MediaDomainError(
          "MEDIA_UPLOAD_MISMATCH",
          "存储中的文件与完成信息不一致",
          422
        );
      }
    }

    return this.repository.completeUpload({
      ownerUserId: input.userId,
      uploadId,
      completeIdempotencyHash: idempotencyHash,
      completeRequestHash: requestHash,
      etag: completion.etag,
      now
    });
  }

  getMedia(userId: string, mediaId: unknown): Promise<MediaView> {
    return this.repository.getMedia(
      userId,
      this.uuid(mediaId, "MEDIA_ID_INVALID")
    );
  }

  private uploadSpec(body: Record<string, unknown>): MediaUploadSpec {
    if (typeof body.purpose !== "string" || !PURPOSES.has(body.purpose as MediaPurpose)) {
      throw new MediaDomainError(
        "MEDIA_PURPOSE_INVALID",
        "媒体用途无效",
        400
      );
    }
    if (
      typeof body.mediaType !== "string" ||
      !MEDIA_TYPES.has(body.mediaType as MediaType)
    ) {
      throw new MediaDomainError("MEDIA_TYPE_INVALID", "媒体类型无效", 400);
    }
    const purpose = body.purpose as MediaPurpose;
    const mediaType = body.mediaType as MediaType;
    if (
      (purpose === "avatar" || purpose === "background") &&
      mediaType !== "image"
    ) {
      throw new MediaDomainError(
        "MEDIA_TYPE_INVALID",
        "头像和背景墙只能使用图片",
        422
      );
    }
    if (mediaType === "sticker" && purpose !== "chat") {
      throw new MediaDomainError(
        "MEDIA_TYPE_INVALID",
        "表情包只能用于聊天",
        422
      );
    }

    const fileName =
      typeof body.fileName === "string" ? body.fileName.trim() : "";
    if (!fileName || fileName.length > 200 || /[/\\\0]/.test(fileName)) {
      throw new MediaDomainError(
        "MEDIA_FILE_NAME_INVALID",
        "文件名无效",
        400
      );
    }
    const contentType =
      typeof body.contentType === "string"
        ? body.contentType.trim().toLowerCase()
        : "";
    if (!CONTENT_TYPES[mediaType].has(contentType)) {
      throw new MediaDomainError(
        "MEDIA_CONTENT_TYPE_INVALID",
        "暂不支持这种文件格式",
        415
      );
    }
    const bytes = this.positiveInteger(body.bytes, "MEDIA_BYTES_INVALID");
    if (bytes > MAX_BYTES[mediaType]) {
      throw new MediaDomainError(
        "MEDIA_FILE_TOO_LARGE",
        "文件超过当前大小限制",
        413
      );
    }
    const sha256 =
      typeof body.sha256 === "string" ? body.sha256.trim().toLowerCase() : "";
    if (!SHA256_PATTERN.test(sha256)) {
      throw new MediaDomainError(
        "MEDIA_SHA256_INVALID",
        "文件校验值无效",
        400
      );
    }
    const durationMs = this.optionalInteger(
      body.durationMs,
      "MEDIA_DURATION_INVALID"
    );
    if (mediaType === "video" && durationMs === null) {
      throw new MediaDomainError(
        "MEDIA_DURATION_REQUIRED",
        "视频缺少时长信息",
        422
      );
    }
    if (mediaType === "video" && durationMs !== null && durationMs > 20_000) {
      throw new MediaDomainError(
        "MEDIA_VIDEO_TOO_LONG",
        "视频最长为20秒",
        413
      );
    }
    const width = this.optionalInteger(body.width, "MEDIA_WIDTH_INVALID", false);
    const height = this.optionalInteger(
      body.height,
      "MEDIA_HEIGHT_INVALID",
      false
    );
    if (mediaType === "video" && width !== null && height !== null) {
      const longSide = Math.max(width, height);
      const shortSide = Math.min(width, height);
      if (longSide > 1920 || shortSide > 1080) {
        throw new MediaDomainError(
          "MEDIA_VIDEO_RESOLUTION_TOO_HIGH",
          "视频最高支持1080p",
          413
        );
      }
    }
    return {
      purpose,
      mediaType,
      fileName,
      contentType,
      bytes,
      sha256,
      durationMs,
      width,
      height
    };
  }

  private completion(body: Record<string, unknown>): {
    etag: string;
    bytes: number;
    sha256: string;
  } {
    const etag =
      typeof body.etag === "string" ? this.normalizeEtag(body.etag) : "";
    if (!etag || etag.length > 256) {
      throw new MediaDomainError("MEDIA_ETAG_INVALID", "文件标识无效", 400);
    }
    const bytes = this.positiveInteger(body.bytes, "MEDIA_BYTES_INVALID");
    const sha256 =
      typeof body.sha256 === "string" ? body.sha256.trim().toLowerCase() : "";
    if (!SHA256_PATTERN.test(sha256)) {
      throw new MediaDomainError(
        "MEDIA_SHA256_INVALID",
        "文件校验值无效",
        400
      );
    }
    return { etag, bytes, sha256 };
  }

  private canonicalUpload(spec: MediaUploadSpec): string {
    return JSON.stringify([
      spec.purpose,
      spec.mediaType,
      spec.fileName,
      spec.contentType,
      spec.bytes,
      spec.sha256,
      spec.durationMs,
      spec.width,
      spec.height
    ]);
  }

  private objectKey(
    userId: string,
    uploadId: string,
    spec: MediaUploadSpec
  ): string {
    const extension = this.extension(spec.contentType);
    return `temporary/${userId}/${uploadId}/${spec.sha256}.${extension}`;
  }

  private extension(contentType: string): string {
    const extensions: Record<string, string> = {
      "image/jpeg": "jpg",
      "image/png": "png",
      "image/webp": "webp",
      "image/heic": "heic",
      "image/heif": "heif",
      "image/gif": "gif",
      "audio/aac": "aac",
      "audio/mp4": "m4a",
      "audio/mpeg": "mp3",
      "audio/ogg": "ogg",
      "audio/x-m4a": "m4a",
      "video/mp4": "mp4",
      "video/quicktime": "mov"
    };
    return extensions[contentType] ?? "bin";
  }

  private positiveInteger(value: unknown, code: string): number {
    if (
      typeof value !== "number" ||
      !Number.isSafeInteger(value) ||
      value < 1
    ) {
      throw new MediaDomainError(code, "数值格式无效", 400);
    }
    return value;
  }

  private optionalInteger(
    value: unknown,
    code: string,
    allowZero = true
  ): number | null {
    if (value === undefined || value === null) return null;
    if (
      typeof value !== "number" ||
      !Number.isSafeInteger(value) ||
      value < (allowZero ? 0 : 1)
    ) {
      throw new MediaDomainError(code, "数值格式无效", 400);
    }
    return value;
  }

  private uuid(value: unknown, code: string): string {
    if (typeof value !== "string" || !UUID_PATTERN.test(value)) {
      throw new MediaDomainError(code, "标识格式无效", 400);
    }
    return value;
  }

  private idempotencyKey(value?: string): string {
    const key = value?.trim();
    if (!key || key.length > 200) {
      throw new MediaDomainError(
        "IDEMPOTENCY_KEY_REQUIRED",
        "请求缺少有效的幂等键",
        400
      );
    }
    return key;
  }

  private normalizeEtag(value: string): string {
    return value.trim().replace(/^"|"$/g, "");
  }
}
