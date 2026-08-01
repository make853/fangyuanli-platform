import { Injectable } from "@nestjs/common";
import { randomUUID } from "node:crypto";
import { DatabaseService } from "../database/database.service.js";
import type { QueryExecutor } from "../database/database.types.js";
import type { MediaPurpose, MediaType } from "./media.types.js";
import {
  MediaProcessingLeaseLost,
  type MediaProcessingJob,
  type MediaProcessingResult
} from "./media-processing.types.js";

type ClaimedJobRow = {
  job_id: string;
  media_asset_id: string;
  owner_user_id: string;
  purpose: MediaPurpose;
  media_type: MediaType;
  object_key: string;
  content_type: string;
  bytes: string;
  width: number | null;
  height: number | null;
  attempt_count: number;
  lease_owner: string;
  lease_expires_at: Date;
};

@Injectable()
export class MediaProcessingRepository {
  constructor(private readonly database: DatabaseService) {}

  async enqueue(
    mediaAssetId: string,
    now: Date,
    executor: QueryExecutor = this.database
  ): Promise<void> {
    await executor.query(
      `INSERT INTO media_processing_jobs (
         id, media_asset_id, status, available_at, created_at, updated_at
       )
       VALUES ($1, $2, 'pending', $3, $3, $3)
       ON CONFLICT (media_asset_id) DO NOTHING`,
      [randomUUID(), mediaAssetId, now]
    );
  }

  async claimNext(input: {
    workerId: string;
    now: Date;
    leaseDurationMs: number;
  }): Promise<MediaProcessingJob | null> {
    const leaseExpiresAt = new Date(
      input.now.getTime() + input.leaseDurationMs
    );
    return this.database.transaction(async (client) => {
      const result = await client.query<ClaimedJobRow>(
        `WITH candidate AS (
           SELECT jobs.id
             FROM media_processing_jobs jobs
             JOIN media_assets assets
               ON assets.id = jobs.media_asset_id
              AND assets.deleted_at IS NULL
            WHERE (
                    jobs.status IN ('pending', 'retry')
                    AND jobs.available_at <= $1
                  )
               OR (
                    jobs.status = 'processing'
                    AND jobs.lease_expires_at <= $1
                  )
            ORDER BY jobs.available_at ASC, jobs.created_at ASC
            FOR UPDATE SKIP LOCKED
            LIMIT 1
         ), claimed AS (
           UPDATE media_processing_jobs jobs
              SET status = 'processing',
                  attempt_count = attempt_count + 1,
                  lease_owner = $2,
                  lease_expires_at = $3,
                  updated_at = $1
             FROM candidate
            WHERE jobs.id = candidate.id
            RETURNING jobs.id, jobs.media_asset_id, jobs.attempt_count,
                      jobs.lease_owner, jobs.lease_expires_at
         )
         SELECT claimed.id AS job_id,
                assets.id AS media_asset_id,
                assets.owner_user_id,
                assets.purpose,
                assets.media_type,
                assets.object_key,
                assets.content_type,
                assets.bytes,
                assets.width,
                assets.height,
                claimed.attempt_count,
                claimed.lease_owner,
                claimed.lease_expires_at
           FROM claimed
           JOIN media_assets assets ON assets.id = claimed.media_asset_id
          WHERE assets.deleted_at IS NULL`,
        [input.now, input.workerId, leaseExpiresAt]
      );
      const row = result.rows[0];
      return row ? this.job(row) : null;
    });
  }

  async complete(input: {
    jobId: string;
    workerId: string;
    result: MediaProcessingResult;
    now: Date;
  }): Promise<void> {
    await this.database.transaction(async (client) => {
      const assetId = await this.completeOwnedJob(
        client,
        input.jobId,
        input.workerId,
        input.now
      );
      const updated = await client.query<{ id: string }>(
        `UPDATE media_assets
            SET processing_status = 'ready',
                display_object_key = $2,
                thumbnail_object_key = $3,
                width = $4,
                height = $5,
                bytes = $6,
                processing_failure_code = NULL,
                processing_completed_at = $7,
                updated_at = $7
          WHERE id = $1 AND deleted_at IS NULL
          RETURNING id`,
        [
          assetId,
          input.result.displayObjectKey,
          input.result.thumbnailObjectKey,
          input.result.width,
          input.result.height,
          input.result.displayBytes,
          input.now
        ]
      );
      if (!updated.rows[0]) {
        throw new Error("Media asset disappeared while completing processing");
      }
    });
  }

  async fail(input: {
    jobId: string;
    workerId: string;
    errorCode: string;
    retryAt: Date | null;
    now: Date;
  }): Promise<void> {
    await this.database.transaction(async (client) => {
      const result = await client.query<{ media_asset_id: string }>(
        `UPDATE media_processing_jobs
            SET status = $4,
                available_at = COALESCE($5, available_at),
                lease_owner = NULL,
                lease_expires_at = NULL,
                last_error_code = $3,
                updated_at = $6
          WHERE id = $1
            AND status = 'processing'
            AND lease_owner = $2
          RETURNING media_asset_id`,
        [
          input.jobId,
          input.workerId,
          input.errorCode,
          input.retryAt ? "retry" : "failed",
          input.retryAt,
          input.now
        ]
      );
      const row = result.rows[0];
      if (!row) throw new MediaProcessingLeaseLost();
      if (input.retryAt) return;
      await client.query(
        `UPDATE media_assets
            SET processing_status = 'failed',
                processing_failure_code = $2,
                updated_at = $3
          WHERE id = $1 AND deleted_at IS NULL`,
        [row.media_asset_id, input.errorCode, input.now]
      );
    });
  }

  private async completeOwnedJob(
    client: QueryExecutor,
    jobId: string,
    workerId: string,
    now: Date
  ): Promise<string> {
    const result = await client.query<{ media_asset_id: string }>(
      `UPDATE media_processing_jobs
          SET status = 'completed',
              lease_owner = NULL,
              lease_expires_at = NULL,
              last_error_code = NULL,
              completed_at = $3,
              updated_at = $3
        WHERE id = $1
          AND status = 'processing'
          AND lease_owner = $2
        RETURNING media_asset_id`,
      [jobId, workerId, now]
    );
    const row = result.rows[0];
    if (!row) throw new MediaProcessingLeaseLost();
    return row.media_asset_id;
  }

  private job(row: ClaimedJobRow): MediaProcessingJob {
    return {
      jobId: row.job_id,
      mediaId: row.media_asset_id,
      ownerUserId: row.owner_user_id,
      purpose: row.purpose,
      mediaType: row.media_type,
      sourceObjectKey: row.object_key,
      contentType: row.content_type,
      bytes: Number(row.bytes),
      width: row.width,
      height: row.height,
      attemptCount: row.attempt_count,
      leaseOwner: row.lease_owner,
      leaseExpiresAt: row.lease_expires_at
    };
  }
}
