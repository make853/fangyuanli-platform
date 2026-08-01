import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import test from "node:test";
import { Pool } from "pg";
import { ProfileRepository } from "../profiles/profile.repository.js";
import { ProfileDomainError } from "../profiles/profile.types.js";
import { DatabaseService } from "./database.service.js";
import { requireDatabaseUrl } from "./environment.js";

test(
  "profile media binding is atomic, purpose-safe and gives replaced media a grace period",
  { skip: process.env.RUN_DATABASE_INTEGRATION_TESTS !== "true" },
  async () => {
    const pool = new Pool({
      application_name: "fangyuanli-profile-media-integration-test",
      connectionString: requireDatabaseUrl(process.env),
      max: 2
    });
    const database = new DatabaseService(pool);
    const repository = new ProfileRepository(database);
    const userId = randomUUID();
    const firstAvatarId = randomUUID();
    const secondAvatarId = randomUUID();
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
        `INSERT INTO user_profiles (user_id, nickname)
         VALUES ($1, '媒体测试用户')`,
        [userId]
      );
      await database.query(
        `INSERT INTO user_privacy_settings (user_id) VALUES ($1)`,
        [userId]
      );
      for (const mediaId of [firstAvatarId, secondAvatarId]) {
        await database.query(
          `INSERT INTO media_assets (
             id, owner_user_id, purpose, media_type, object_key, content_type,
             sha256, original_file_name, width, height, bytes,
             processing_status, display_object_key, thumbnail_object_key,
             expires_at, created_at
           ) VALUES (
             $1, $2, 'avatar', 'image', $3, 'image/jpeg', $4, 'avatar.jpg',
             512, 512, 1024, 'ready', $5, $6, $7, $8
           )`,
          [
            mediaId,
            userId,
            `temporary/${userId}/${mediaId}/avatar.jpg`,
            mediaId.replaceAll("-", "").padEnd(64, "a").slice(0, 64),
            `processed/${userId}/${mediaId}/avatar-512.webp`,
            `processed/${userId}/${mediaId}/avatar-128.webp`,
            new Date(now.getTime() + 60 * 60 * 1000),
            now
          ]
        );
      }

      const first = await repository.updateProfile(
        userId,
        { expectedVersion: 1, avatarMediaId: firstAvatarId },
        now
      );
      assert.equal(first.avatarReference?.mediaId, firstAvatarId);

      const replaceAt = new Date(now.getTime() + 1_000);
      const second = await repository.updateProfile(
        userId,
        { expectedVersion: 2, avatarMediaId: secondAvatarId },
        replaceAt
      );
      assert.equal(second.avatarReference?.mediaId, secondAvatarId);

      const retention = await database.query<{
        id: string;
        expires_at: Date | null;
      }>(
        `SELECT id, expires_at
           FROM media_assets
          WHERE id = ANY($1::uuid[])
          ORDER BY id`,
        [[firstAvatarId, secondAvatarId]]
      );
      const firstAvatar = retention.rows.find((row) => row.id === firstAvatarId);
      const secondAvatar = retention.rows.find((row) => row.id === secondAvatarId);
      assert.ok(firstAvatar?.expires_at);
      assert.ok(
        firstAvatar.expires_at.getTime() >=
          replaceAt.getTime() + 24 * 60 * 60 * 1000
      );
      assert.equal(secondAvatar?.expires_at, null);

      await assert.rejects(
        repository.updateProfile(
          userId,
          { expectedVersion: 3, backgroundMediaId: secondAvatarId },
          new Date(replaceAt.getTime() + 1_000)
        ),
        (error: unknown) =>
          error instanceof ProfileDomainError &&
          error.code === "PROFILE_MEDIA_PURPOSE_MISMATCH"
      );
      const version = await database.query<{ profile_version: number }>(
        "SELECT profile_version FROM user_profiles WHERE user_id = $1",
        [userId]
      );
      assert.equal(version.rows[0]?.profile_version, 3);
    } finally {
      await database.query("DELETE FROM user_profiles WHERE user_id = $1", [
        userId
      ]);
      await database.query(
        "DELETE FROM user_privacy_settings WHERE user_id = $1",
        [userId]
      );
      await database.query(
        "DELETE FROM media_assets WHERE id = ANY($1::uuid[])",
        [[firstAvatarId, secondAvatarId]]
      );
      await database.query("DELETE FROM users WHERE id = $1", [userId]);
      await database.onApplicationShutdown();
    }
  }
);
