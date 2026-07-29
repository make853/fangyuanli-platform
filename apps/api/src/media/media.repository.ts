import { Injectable, OnApplicationShutdown } from "@nestjs/common";
import { randomUUID } from "node:crypto";
import { Pool, type PoolClient, type QueryResult, type QueryResultRow } from "pg";
import { requireDatabaseUrl } from "../database/environment.js";
import {
  MediaDomainError,
  type MediaType,
  type MediaUploadSession,
  type MediaUploadSpec,
  type MediaView
} from "./media.types.js";

type QueryClient = {
  query<R extends QueryResultRow = QueryResultRow>(
    text: string,
    values?: unknown[]
  ): Promise<QueryResult<R>>;
};

type UploadRow = {
  id: string;
  owner_user_id: string;
  purpose: MediaUploadSpec["purpose"];
  media_type: MediaType;
  original_file_name: string;
  content_type: string;
  expected_bytes: string;
  expected_sha256: string;
  duration_ms: number | null;
  width: number | null;
  height: number | null;
  object_key: string;
  status: MediaUploadSession["status"];
  create_request_hash: string;
  complete_idempotency_hash: string | null;
  complete_request_hash: string | null;
  media_asset_id: string | null;
  etag: string | null;
  expires_at: Date;
};

type MediaRow = {
  id: string;
  owner_user_id: string | null;
  media_type: MediaType;
  processing_status: MediaView["status"];
  object_key: string;
  thumbnail_object_key: string | null;
  cover_object_key: string | null;
  width: number | null;
  height: number | null;
  duration_ms: number | null;
  expires_at: Date | null;
};

@Injectable()
export class MediaRepository implements OnApplicationShutdown {
  private readonly pool = new Pool({
    connectionString: requireDatabaseUrl(process.env),
    max: 10
  });

  async onApplicationShutdown(): Promise<void> {
    await this.pool.end();
  }

  async createUpload(input: {
    uploadId: string;
    ownerUserId: string;
    spec: MediaUploadSpec;
    objectKey: string;
    createIdempotencyHash: string;
    createRequestHash: string;
    expiresAt: Date;
    now: Date;
  }): Promise<MediaUploadSession> {
    return this.transaction(async (client) => {
      await client.query(
        `INSERT INTO media_upload_sessions (
           id, owner_user_id, purpose, media_type, original_file_name,
           content_type, expected_bytes, expected_sha256, duration_ms, width,
           height, object_key, create_idempotency_hash, create_request_hash,
           expires_at, created_at, updated_at
         )
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13,
                 $14, $15, $16, $16)
         ON CONFLICT (owner_user_id, create_idempotency_hash) DO NOTHING`,
        [
          input.uploadId,
          input.ownerUserId,
          input.spec.purpose,
          input.spec.mediaType,
          input.spec.fileName,
          input.spec.contentType,
          input.spec.bytes,
          input.spec.sha256,
          input.spec.durationMs,
          input.spec.width,
          input.spec.height,
          input.objectKey,
          input.createIdempotencyHash,
          input.createRequestHash,
          input.expiresAt,
          input.now
        ]
      );
      const result = await client.query<UploadRow>(
        `SELECT id, owner_user_id, purpose, media_type, original_file_name,
                content_type, expected_bytes, expected_sha256, duration_ms,
                width, height, object_key, status, create_request_hash,
                complete_idempotency_hash, complete_request_hash,
                media_asset_id, etag, expires_at
           FROM media_upload_sessions
          WHERE owner_user_id = $1
            AND create_idempotency_hash = $2`,
        [input.ownerUserId, input.createIdempotencyHash]
      );
      const row = result.rows[0];
      if (!row) {
        throw new Error("Failed to create media upload session");
      }
      return this.uploadSession(row);
    });
  }

  async getUpload(
    ownerUserId: string,
    uploadId: string
  ): Promise<MediaUploadSession> {
    const result = await this.pool.query<UploadRow>(
      `SELECT id, owner_user_id, purpose, media_type, original_file_name,
              content_type, expected_bytes, expected_sha256, duration_ms,
              width, height, object_key, status, create_request_hash,
              complete_idempotency_hash, complete_request_hash,
              media_asset_id, etag, expires_at
         FROM media_upload_sessions
        WHERE id = $1 AND owner_user_id = $2`,
      [uploadId, ownerUserId]
    );
    const row = result.rows[0];
    if (!row) {
      throw new MediaDomainError(
        "MEDIA_UPLOAD_NOT_FOUND",
        "上传任务不存在",
        404
      );
    }
    return this.uploadSession(row);
  }

  async completeUpload(input: {
    ownerUserId: string;
    uploadId: string;
    completeIdempotencyHash: string;
    completeRequestHash: string;
    etag: string;
    now: Date;
  }): Promise<MediaView> {
    return this.transaction(async (client) => {
      const locked = await client.query<UploadRow>(
        `SELECT id, owner_user_id, purpose, media_type, original_file_name,
                content_type, expected_bytes, expected_sha256, duration_ms,
                width, height, object_key, status, create_request_hash,
                complete_idempotency_hash, complete_request_hash,
                media_asset_id, etag, expires_at
           FROM media_upload_sessions
          WHERE id = $1 AND owner_user_id = $2
          FOR UPDATE`,
        [input.uploadId, input.ownerUserId]
      );
      const row = locked.rows[0];
      if (!row) {
        throw new MediaDomainError(
          "MEDIA_UPLOAD_NOT_FOUND",
          "上传任务不存在",
          404
        );
      }
      if (
        row.complete_idempotency_hash &&
        (row.complete_idempotency_hash !== input.completeIdempotencyHash ||
          row.complete_request_hash !== input.completeRequestHash)
      ) {
        throw new MediaDomainError(
          "IDEMPOTENCY_KEY_REUSED",
          "幂等键已用于其他完成请求",
          409
        );
      }
      if (row.media_asset_id) {
        return this.loadMedia(client, input.ownerUserId, row.media_asset_id);
      }

      const mediaId = randomUUID();
      await client.query(
        `INSERT INTO media_assets (
           id, owner_user_id, purpose, media_type, object_key, content_type,
           sha256, original_file_name, width, height, duration_ms, bytes,
           processing_status, created_at
         )
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12,
                 'processing', $13)`,
        [
          mediaId,
          row.owner_user_id,
          row.purpose,
          row.media_type,
          row.object_key,
          row.content_type,
          row.expected_sha256,
          row.original_file_name,
          row.width,
          row.height,
          row.duration_ms,
          Number(row.expected_bytes),
          input.now
        ]
      );
      await client.query(
        `UPDATE media_upload_sessions
            SET status = 'completed',
                complete_idempotency_hash = $3,
                complete_request_hash = $4,
                media_asset_id = $5,
                etag = $6,
                updated_at = $7
          WHERE id = $1 AND owner_user_id = $2`,
        [
          input.uploadId,
          input.ownerUserId,
          input.completeIdempotencyHash,
          input.completeRequestHash,
          mediaId,
          input.etag,
          input.now
        ]
      );
      return this.loadMedia(client, input.ownerUserId, mediaId);
    });
  }

  async getMedia(ownerUserId: string, mediaId: string): Promise<MediaView> {
    return this.loadMedia(this.pool, ownerUserId, mediaId);
  }

  private async loadMedia(
    client: QueryClient,
    ownerUserId: string,
    mediaId: string
  ): Promise<MediaView> {
    const result = await client.query<MediaRow>(
      `SELECT id, owner_user_id, media_type, processing_status, object_key,
              thumbnail_object_key, cover_object_key, width, height,
              duration_ms, expires_at
         FROM media_assets
        WHERE id = $1
          AND owner_user_id = $2
          AND deleted_at IS NULL`,
      [mediaId, ownerUserId]
    );
    const row = result.rows[0];
    if (!row) {
      throw new MediaDomainError("MEDIA_NOT_FOUND", "媒体不存在", 404);
    }
    return {
      mediaId: row.id,
      mediaType: row.media_type,
      status: row.processing_status,
      url: null,
      thumbnailUrl: null,
      coverUrl: null,
      width: row.width,
      height: row.height,
      durationMs: row.duration_ms,
      expiresAt: row.expires_at?.toISOString() ?? null
    };
  }

  private uploadSession(row: UploadRow): MediaUploadSession {
    return {
      uploadId: row.id,
      ownerUserId: row.owner_user_id,
      purpose: row.purpose,
      mediaType: row.media_type,
      fileName: row.original_file_name,
      contentType: row.content_type,
      bytes: Number(row.expected_bytes),
      sha256: row.expected_sha256,
      durationMs: row.duration_ms,
      width: row.width,
      height: row.height,
      objectKey: row.object_key,
      status: row.status,
      createRequestHash: row.create_request_hash,
      completeIdempotencyHash: row.complete_idempotency_hash,
      completeRequestHash: row.complete_request_hash,
      mediaAssetId: row.media_asset_id,
      etag: row.etag,
      expiresAt: row.expires_at
    };
  }

  private async transaction<T>(
    action: (client: PoolClient) => Promise<T>
  ): Promise<T> {
    const client = await this.pool.connect();
    try {
      await client.query("BEGIN");
      const result = await action(client);
      await client.query("COMMIT");
      return result;
    } catch (error) {
      await client.query("ROLLBACK");
      throw error;
    } finally {
      client.release();
    }
  }
}
