import { Injectable } from "@nestjs/common";
import { DatabaseService } from "../database/database.service.js";
import type { QueryExecutor } from "../database/database.types.js";
import {
  ProfileDomainError,
  type Gender,
  type PrivacyPatch,
  type PrivacySettingsView,
  type ProfilePatch,
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

  async getProfile(viewerUserId: string, targetUserId: string): Promise<ProfileView> {
    return this.loadProfile(this.database, viewerUserId, targetUserId);
  }

  async updateProfile(
    userId: string,
    patch: ProfilePatch,
    now: Date
  ): Promise<ProfileView> {
    return this.database.transaction(async (client) => {
      const locked = await client.query<{
        nickname: string;
        gender: Gender;
        custom_gender: string | null;
        signature: string | null;
        profile_version: number;
      }>(
        `SELECT nickname, gender, custom_gender, signature, profile_version
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

      await client.query(
        `UPDATE user_profiles
            SET nickname = $2,
                gender = $3,
                custom_gender = $4,
                signature = $5,
                profile_version = profile_version + 1,
                updated_at = $6
          WHERE user_id = $1`,
        [userId, nickname, gender, customGender, signature, now]
      );
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
  ): Promise<ProfileView> {
    const result = await client.query<ProfileRow>(
      `SELECT u.id AS user_id,
              u.fangyuan_number,
              p.nickname,
              p.gender,
              p.custom_gender,
              p.signature,
              p.profile_version,
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

  private profileView(row: ProfileRow, isSelf: boolean): ProfileView {
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
      avatar: null,
      fangyuanNumber: full ? row.fangyuan_number : null,
      nickname: full ? row.nickname : null,
      gender: full ? row.gender : "hidden",
      signature: row.signature ?? "",
      background: null,
      profileVisibility: full ? "full" : "limited",
      profileVersion: row.profile_version,
      relationship,
      allowedActions: this.allowedActions(relationship.state, relationship)
    };
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
