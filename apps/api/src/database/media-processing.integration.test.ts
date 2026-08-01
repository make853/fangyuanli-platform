import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";
import { Pool } from "pg";
import { MediaProcessingRepository } from "../media/media-processing.repository.js";
import { DatabaseService } from "./database.service.js";
import { requireDatabaseUrl } from "./environment.js";

test(
  "media jobs survive retry, lease handoff and transactional completion",
  { skip: process.env.RUN_DATABASE_INTEGRATION_TESTS !== "true" },
  async () => {
    const pool = new Pool({
      application_name: "fangyuanli-media-processing-integration-test",
      connectionString: requireDatabaseUrl(process.env),
      max: 2
    });
    const database = new DatabaseService(pool);
    const repository = new MediaProcessingRepository(database);
    const userId = randomUUID();
    const mediaId = randomUUID();
    const now = new Date();

    try {
      await database.query(
        `INSERT INTO users (
           id, fangyuan_number, phone_ciphertext, phone_hash, status
         ) VALUES ($1, $2, $3, $4, 'active')`,
        [
          userId,
          `FY${userId.replaceAll("-", "").slice(0, 12)}`,
          `ciphertext:${userId}`,
          `hash:${userId}`
        ]
      );
      await database.query(
        `INSERT INTO media_assets (
           id, owner_user_id, purpose, media_type, object_key, content_type,
           sha256, original_file_name, width, height, bytes,
           processing_status, created_at
         ) VALUES (
           $1, $2, 'avatar', 'image', $3, 'image/jpeg', $4, 'avatar.jpg',
           1200, 1200, 1024, 'processing', $5
         )`,
        [
          mediaId,
          userId,
          `temporary/${userId}/${mediaId}/avatar.jpg`,
          "a".repeat(64),
          now
        ]
      );
      await repository.enqueue(mediaId, now);

      const first = await repository.claimNext({
        workerId: "worker-a",
        now,
        leaseDurationMs: 60_000
      });
      assert.equal(first?.mediaId, mediaId);
      assert.equal(first?.attemptCount, 1);
      assert.equal(
        await repository.claimNext({
          workerId: "worker-b",
          now,
          leaseDurationMs: 60_000
        }),
        null
      );

      await repository.fail({
        jobId: first!.jobId,
        workerId: "worker-a",
        errorCode: "MEDIA_SOURCE_UNAVAILABLE",
        retryAt: new Date(now.getTime() - 1),
        now
      });
      const second = await repository.claimNext({
        workerId: "worker-b",
        now,
        leaseDurationMs: 60_000
      });
      assert.equal(second?.mediaId, mediaId);
      assert.equal(second?.attemptCount, 2);

      await repository.complete({
        jobId: second!.jobId,
        workerId: "worker-b",
        result: {
          displayObjectKey: `processed/${userId}/${mediaId}/avatar-512.webp`,
          thumbnailObjectKey: `processed/${userId}/${mediaId}/avatar-128.webp`,
          width: 512,
          height: 512,
          displayBytes: 512
        },
        now
      });

      const result = await database.query<{
        processing_status: string;
        display_object_key: string;
        thumbnail_object_key: string;
        job_status: string;
        attempt_count: number;
      }>(
        `SELECT assets.processing_status,
                assets.display_object_key,
                assets.thumbnail_object_key,
                jobs.status AS job_status,
                jobs.attempt_count
           FROM media_assets assets
           JOIN media_processing_jobs jobs
             ON jobs.media_asset_id = assets.id
          WHERE assets.id = $1`,
        [mediaId]
      );
      assert.deepEqual(result.rows[0], {
        processing_status: "ready",
        display_object_key: `processed/${userId}/${mediaId}/avatar-512.webp`,
        thumbnail_object_key: `processed/${userId}/${mediaId}/avatar-128.webp`,
        job_status: "completed",
        attempt_count: 2
      });
    } finally {
      await database.query(
        "DELETE FROM media_processing_jobs WHERE media_asset_id = $1",
        [mediaId]
      );
      await database.query("DELETE FROM media_assets WHERE id = $1", [mediaId]);
      await database.query("DELETE FROM users WHERE id = $1", [userId]);
      await database.onApplicationShutdown();
    }
  }
);
