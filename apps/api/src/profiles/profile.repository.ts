import { Injectable } from "@nestjs/common";
import { DatabaseService } from "../database/database.service.js";
import type { QueryExecutor } from "../database/database.types.js";
import type { MediaDeliveryReference, MediaStatus, MediaType } from "../media/media.types.js";
import {
  ProfileDomainError,
  type Gender,
  type PrivacyPatch,
  type PrivacySettingsView,
  type ProfilePatch,
  type ProfileProjection,
  type ProfileView,
  type RelationshipState
} from "./profile.types.js";

type ProfileRow = {
  user_id: string;
  fangyuan_number: string;
  nickname: string;
  gender: Gender;
  custom_gender: string | null;
  signature: string | null;
  profile_version: number;
  avatar_id: string | null;
  avatar_media_type: MediaType | null;
  avatar_status: MediaStatus | null;
  avatar_display_object_key: string | null;
  avatar_thumbnail_object_key: string | null;
  avatar_cover_object_key: string | null;
  avatar_width: number | null;
  avatar_height: number | null;
  avatar_duration_ms: number | null;
  background_id: string | null;
  background_media_type: MediaType | null;
  background_status: MediaStatus | null;
  background_display_object_key: string | null;
  background_thumbnail_object_key: string | null;
  background_cover_object_key: string | null;
  background_width: number | null;
  background_height: number | null;
  background_duration_ms: number | null;
  strangers_can_view_profile: boolean;
  is_friend: boolean;
  request_pending: boolean;
  is_blocked_by_me: boolean;
  has_blocked_me: boolean;
  can_view_my_posts: boolean;
};

type PrivacyRow = {
  strangers_can_view_profile: boolean;
  searchable_by_fangyuan_number: boolean;
  global_group_muted: boolean;
  updated_at: Date;
};

@Injectable()
export class ProfileRepository {
  constructor(private readonly database: DatabaseService) {}

  async getProfile(
    viewerUserId: string,
    targetUserId: string
  ): Promise<ProfileProjection> {
    return this.loadProfile(this.database, viewerUserId, targetUserId);
  }

  async updateProfile(
    userId: string,
    patch: ProfilePatch,
    now: Date
  ): Promise<ProfileProjection> {
    return this.database.transaction(async (client) => {
      const locked = await client.query<{
        nickname: string;
        gender: Gender;
        custom_gender: string | null;
        signature: string | null;
        profile_version: number;
        avatar_media_id: string | null;
        background_media_id: string | null;
      }>(
        `SELECT nickname, gender, custom_gender, signature, profile_version,
                avatar_media_id, background_media_id
           FROM user_profiles
          WHERE user_id = $1
          FOR UPDATE`,
        [userId]
      );
      const current = locked.rows[0];
      if (!current) {
        throw new ProfileDomainError(
          "PROFILE_NOT_FOUND",
          "个人资料不存在",
          404
        );
      }

      if (current.profile_version !== patch.expectedVersion) {
        throw new ProfileDomainError(
          "PROFILE_VERSION_CONFLICT",
          "资料已经在其他设备更新，请刷新后重试",
          409
        );
      }

      const nickname = patch.nickname ?? current.nickname;
      const gender = patch.gender ?? current.gender;
      const customGender =
        patch.gender === undefined
          ? patch.customGender === undefined
            ? current.custom_gender
            : patch.customGender
          : gender === "custom"
            ? (patch.customGender ?? current.custom_gender)
            : null;
      const signature = patch.signature ?? current.signature ?? "";

      if (patch.avatarMediaId !== undefined && patch.avatarMediaId !== null) {
        await this.validateProfileMedia(
          client,
          userId,
          patch.avatarMediaId,
          "avatar"
        );
      }
      if (
        patch.backgroundMediaId !== undefined &&
        patch.backgroundMediaId !== null
      ) {
        await this.validateProfileMedia(
          client,
          userId,
          patch.backgroundMediaId,
          "background"
        );
      }
      const avatarMediaId =
        patch.avatarMediaId === undefined
          ? current.avatar_media_id
          : patch.avatarMediaId;
      const backgroundMediaId =
        patch.backgroundMediaId === undefined
          ? current.background_media_id
          : patch.backgroundMediaId;

      await client.query(
        `UPDATE user_profiles
            SET nickname = $2,
                gender = $3,
                custom_gender = $4,
                signature = $5,
                avatar_media_id = $6,
                background_media_id = $7,
                profile_version = profile_version + 1,
                updated_at = $8
          WHERE user_id = $1`,
        [
          userId,
          nickname,
          gender,
          customGender,
          signature,
          avatarMediaId,
          backgroundMediaId,
          now
        ]
      );
      await this.updateMediaRetention(client, {
        previousMediaId: current.avatar_media_id,
        nextMediaId: avatarMediaId,
        now
      });
      await this.updateMediaRetention(client, {
        previousMediaId: current.background_media_id,
        nextMediaId: backgroundMediaId,
        now
      });
      await client.query(
        `UPDATE users SET updated_at = $2 WHERE id = $1`,
        [userId, now]
      );
      return this.loadProfile(client, userId, userId);
    });
  }

  async getPrivacy(userId: string): Promise<PrivacySettingsView> {
    const result = await this.database.query<PrivacyRow>(
      `SELECT strangers_can_view_profile, searchable_by_fangyuan_number,
              global_group_muted, updated_at
         FROM user_privacy_settings
        WHERE user_id = $1`,
      [userId]
    );
    const row = result.rows[0];
    if (!row) {
      throw new ProfileDomainError(
        "PRIVACY_SETTINGS_NOT_FOUND",
        "隐私设置不存在",
        404
      );
    }
    return this.privacyView(row);
  }

  async updatePrivacy(
    userId: string,
    patch: PrivacyPatch,
    now: Date
  ): Promise<PrivacySettingsView> {
    const result = await this.database.query<PrivacyRow>(
      `UPDATE user_privacy_settings
          SET strangers_can_view_profile =
                COALESCE($2, strangers_can_view_profile),
              searchable_by_fangyuan_number =
                COALESCE($3, searchable_by_fangyuan_number),
              global_group_muted =
                COALESCE($4, global_group_muted),
              updated_at = $5
        WHERE user_id = $1
        RETURNING strangers_can_view_profile, searchable_by_fangyuan_number,
                  global_group_muted, updated_at`,
      [
        userId,
        patch.strangersCanViewProfile ?? null,
        patch.searchableByFangyuanNumber ?? null,
        patch.globalGroupMuted ?? null,
        now
      ]
    );
    const row = result.rows[0];
    if (!row) {
      throw new ProfileDomainError(
        "PRIVACY_SETTINGS_NOT_FOUND",
        "隐私设置不存在",
        404
      );
    }
    return this.privacyView(row);
  }

  private async loadProfile(
    client: QueryExecutor,
    viewerUserId: string,
    targetUserId: string
  ): Promise<ProfileProjection> {
    const result = await client.query<ProfileRow>(
      `SELECT u.id AS user_id,
              u.fangyuan_number,
              p.nickname,
              p.gender,
              p.custom_gender,
              p.signature,
              p.profile_version,
              avatar.id AS avatar_id,
              avatar.media_type AS avatar_media_type,
              avatar.processing_status AS avatar_status,
              avatar.display_object_key AS avatar_display_object_key,
              avatar.thumbnail_object_key AS avatar_thumbnail_object_key,
              avatar.cover_object_key AS avatar_cover_object_key,
              avatar.width AS avatar_width,
              avatar.height AS avatar_height,
              avatar.duration_ms AS avatar_duration_ms,
              background.id AS background_id,
              background.media_type AS background_media_type,
              background.processing_status AS background_status,
              background.display_object_key AS background_display_object_key,
              background.thumbnail_object_key AS background_thumbnail_object_key,
              background.cover_object_key AS background_cover_object_key,
              background.width AS background_width,
              background.height AS background_height,
              background.duration_ms AS background_duration_ms,
              privacy.strangers_can_view_profile,
              EXISTS (
                SELECT 1
                  FROM friendships f
                 WHERE f.status = 'active'
                   AND f.user_low_id = LEAST($1::uuid, u.id)
                   AND f.user_high_id = GREATEST($1::uuid, u.id)
              ) AS is_friend,
              EXISTS (
                SELECT 1
                  FROM friend_requests fr
                 WHERE fr.status = 'pending'
                   AND (
                     (fr.sender_user_id = $1 AND fr.receiver_user_id = u.id)
                     OR (fr.sender_user_id = u.id AND fr.receiver_user_id = $1)
                   )
              ) AS request_pending,
              EXISTS (
                SELECT 1
                  FROM block_relations br
                 WHERE br.blocker_user_id = $1
                   AND br.blocked_user_id = u.id
                   AND br.removed_at IS NULL
              ) AS is_blocked_by_me,
              EXISTS (
                SELECT 1
                  FROM block_relations br
                 WHERE br.blocker_user_id = u.id
                   AND br.blocked_user_id = $1
                   AND br.removed_at IS NULL
              ) AS has_blocked_me,
              COALESCE((
                SELECT fs.can_view_owner_posts
                  FROM friendships f
                  JOIN friend_settings fs
                    ON fs.friendship_id = f.id
                   AND fs.owner_user_id = u.id
                 WHERE f.status = 'active'
                   AND f.user_low_id = LEAST($1::uuid, u.id)
                   AND f.user_high_id = GREATEST($1::uuid, u.id)
              ), false) AS can_view_my_posts
         FROM users u
         JOIN user_profiles p ON p.user_id = u.id
         JOIN user_privacy_settings privacy ON privacy.user_id = u.id
         LEFT JOIN media_assets avatar
           ON avatar.id = p.avatar_media_id
          AND avatar.deleted_at IS NULL
         LEFT JOIN media_assets background
           ON background.id = p.background_media_id
          AND background.deleted_at IS NULL
        WHERE u.id = $2
          AND u.status = 'active'
          AND u.deleted_at IS NULL`,
      [viewerUserId, targetUserId]
    );
    const row = result.rows[0];
    if (!row) {
      throw new ProfileDomainError("PROFILE_NOT_FOUND", "个人资料不存在", 404);
    }
    return this.profileView(row, viewerUserId === targetUserId);
  }

  private profileView(row: ProfileRow, isSelf: boolean): ProfileProjection {
    const relationship = this.relationship(row, isSelf);
    const full =
      isSelf ||
      (relationship.state === "friend" &&
        !relationship.isBlockedByMe &&
        !relationship.hasBlockedMe) ||
      (relationship.state !== "blocked" && row.strangers_can_view_profile);
    return {
      userId: row.user_id,
      displayName: full ? row.nickname : "用户",
      avatarReference: this.mediaReference(row, "avatar"),
      fangyuanNumber: full ? row.fangyuan_number : null,
      nickname: full ? row.nickname : null,
      gender: full ? row.gender : "hidden",
      signature: row.signature ?? "",
      backgroundReference: full ? this.mediaReference(row, "background") : null,
      profileVisibility: full ? "full" : "limited",
      profileVersion: row.profile_version,
      relationship,
      allowedActions: this.allowedActions(relationship.state, relationship)
    };
  }

  private mediaReference(
    row: ProfileRow,
    slot: "avatar" | "background"
  ): MediaDeliveryReference | null {
    const mediaId = row[`${slot}_id`];
    const mediaType = row[`${slot}_media_type`];
    const status = row[`${slot}_status`];
    if (!mediaId || !mediaType || !status) return null;
    return {
      mediaId,
      mediaType,
      status,
      displayObjectKey: row[`${slot}_display_object_key`],
      thumbnailObjectKey: row[`${slot}_thumbnail_object_key`],
      coverObjectKey: row[`${slot}_cover_object_key`],
      width: row[`${slot}_width`],
      height: row[`${slot}_height`],
      durationMs: row[`${slot}_duration_ms`]
    };
  }

  private async validateProfileMedia(
    client: QueryExecutor,
    ownerUserId: string,
    mediaId: string,
    expectedPurpose: "avatar" | "background"
  ): Promise<void> {
    const result = await client.query<{
      owner_user_id: string | null;
      purpose: string;
      media_type: MediaType;
      processing_status: MediaStatus;
      display_object_key: string | null;
      thumbnail_object_key: string | null;
    }>(
      `SELECT owner_user_id, purpose, media_type, processing_status,
              display_object_key, thumbnail_object_key
         FROM media_assets
        WHERE id = $1
          AND deleted_at IS NULL
        FOR UPDATE`,
      [mediaId]
    );
    const media = result.rows[0];
    if (!media) {
      throw new ProfileDomainError(
        "PROFILE_MEDIA_NOT_FOUND",
        "所选图片不存在或已经失效",
        404
      );
    }
    if (media.owner_user_id !== ownerUserId) {
      throw new ProfileDomainError(
        "PROFILE_MEDIA_NOT_OWNED",
        "不能使用其他账号上传的图片",
        403
      );
    }
    if (media.purpose !== expectedPurpose || media.media_type !== "image") {
      throw new ProfileDomainError(
        "PROFILE_MEDIA_PURPOSE_MISMATCH",
        "所选图片用途与资料位置不匹配",
        422
      );
    }
    if (media.processing_status !== "ready") {
      throw new ProfileDomainError(
        "PROFILE_MEDIA_NOT_READY",
        "图片仍在处理中，请稍后重试",
        409
      );
    }
    if (!media.display_object_key || !media.thumbnail_object_key) {
      throw new ProfileDomainError(
        "PROFILE_MEDIA_DERIVATIVE_MISSING",
        "图片处理结果不完整，请重新上传",
        422
      );
    }
  }

  private async updateMediaRetention(
    client: QueryExecutor,
    input: {
      previousMediaId: string | null;
      nextMediaId: string | null;
      now: Date;
    }
  ): Promise<void> {
    if (input.nextMediaId) {
      await client.query(
        `UPDATE media_assets
            SET expires_at = NULL,
                updated_at = $2
          WHERE id = $1`,
        [input.nextMediaId, input.now]
      );
    }
    if (
      !input.previousMediaId ||
      input.previousMediaId === input.nextMediaId
    ) {
      return;
    }
    const graceUntil = new Date(input.now.getTime() + 24 * 60 * 60 * 1000);
    await client.query(
      `UPDATE media_assets media
          SET expires_at = CASE
                WHEN media.expires_at IS NULL OR media.expires_at < $2 THEN $2
                ELSE media.expires_at
              END,
              updated_at = $3
        WHERE media.id = $1
          AND NOT EXISTS (
            SELECT 1
              FROM user_profiles profile
             WHERE profile.avatar_media_id = media.id
                OR profile.background_media_id = media.id
          )`,
      [input.previousMediaId, graceUntil, input.now]
    );
  }

  private relationship(row: ProfileRow, isSelf: boolean): ProfileView["relationship"] {
    let state: RelationshipState;
    if (isSelf) {
      state = "self";
    } else if (row.is_blocked_by_me || row.has_blocked_me) {
      state = "blocked";
    } else if (row.is_friend) {
      state = "friend";
    } else if (row.request_pending) {
      state = "requestPending";
    } else {
      state = "stranger";
    }
    return {
      state,
      canStartDirectChat: state === "friend",
      isBlockedByMe: row.is_blocked_by_me,
      hasBlockedMe: row.has_blocked_me,
      canViewMyPosts: state === "friend" && row.can_view_my_posts
    };
  }

  private allowedActions(
    state: RelationshipState,
    relationship: ProfileView["relationship"]
  ): string[] {
    if (state === "self") return ["editProfile", "editPrivacy"];
    if (state === "friend") return ["startDirectChat", "manageFriend"];
    if (state === "stranger") return ["sendFriendRequest"];
    if (state === "requestPending") return ["viewFriendRequest"];
    if (relationship.isBlockedByMe) return ["unblock"];
    return [];
  }

  private privacyView(row: PrivacyRow): PrivacySettingsView {
    return {
      strangersCanViewProfile: row.strangers_can_view_profile,
      searchableByFangyuanNumber: row.searchable_by_fangyuan_number,
      globalGroupMuted: row.global_group_muted,
      updatedAt: row.updated_at.toISOString()
    };
  }

}
