import { Injectable } from "@nestjs/common";
import type { QueryExecutor } from "../database/database.types.js";
import {
  LocationContextError,
  LocationContextReader
} from "../geo/location-context.js";
import { ConversationDomainError } from "./conversation.types.js";

export type ConversationAccess = {
  conversationId: string;
  type: "direct" | "plaza";
  latestSequence: number;
  notificationMode: "normal" | "muted";
  navigationKey: "friends" | "plaza";
  currentRole: "friend" | "formerFriend" | "blocked" | "nearby" | "history";
  canViewHistory: boolean;
  canSendMessage: boolean;
  peerUserId: string | null;
};

type ConversationRow = {
  id: string;
  type: string;
  latest_sequence: string | number;
  status: string;
};

type DirectAccessRow = {
  friendship_status: "active" | "deleted";
  other_user_id: string;
  blocked: boolean;
  notification_override: "inherit" | "normal" | "muted";
};

type PlazaAccessRow = {
  plaza_id: string;
  current_eligible: boolean;
  has_history: boolean;
  notification_mode: "normal" | "muted";
};

@Injectable()
export class ConversationAccessService {
  constructor(private readonly locationContexts: LocationContextReader) {}

  async authorize(
    client: QueryExecutor,
    input: {
      userId: string;
      conversationId: string;
      capability: "view" | "send" | "read";
      locationContextToken?: string;
      lockConversation?: boolean;
    }
  ): Promise<ConversationAccess> {
    const conversation = await this.conversation(
      client,
      input.conversationId,
      input.lockConversation === true
    );
    if (conversation.type === "direct") {
      return this.authorizeDirect(client, input, conversation);
    }
    if (conversation.type === "plaza") {
      return this.authorizePlaza(client, input, conversation);
    }
    throw new ConversationDomainError(
      "CONVERSATION_TYPE_NOT_READY",
      "当前会话类型尚未开放",
      422
    );
  }

  async recordHistoryEntry(
    client: QueryExecutor,
    input: { userId: string; conversationId: string; now: Date }
  ): Promise<void> {
    await client.query(
      `INSERT INTO user_chat_history_entries (
         user_id, conversation_id, last_entered_at, entry_count
       ) VALUES ($1, $2, $3, 1)
       ON CONFLICT (user_id, conversation_id) DO UPDATE
         SET entry_count = CASE
               WHEN user_chat_history_entries.last_entered_at
                    < EXCLUDED.last_entered_at - interval '30 minutes'
                 THEN user_chat_history_entries.entry_count + 1
               ELSE user_chat_history_entries.entry_count
             END,
             last_entered_at = EXCLUDED.last_entered_at`,
      [input.userId, input.conversationId, input.now]
    );
  }

  async recipientUserIds(
    client: QueryExecutor,
    access: ConversationAccess,
    actorUserId: string
  ): Promise<string[]> {
    if (access.type === "direct") {
      return access.peerUserId
        ? [actorUserId, access.peerUserId]
        : [actorUserId];
    }
    const result = await client.query<{ user_id: string }>(
      `SELECT DISTINCT anchor.user_id
         FROM plaza_grids grid
         JOIN user_plaza_anchors anchor
           ON anchor.grid_version_id = grid.grid_version_id
          AND grid.id = ANY(anchor.plaza_ids)
        WHERE grid.conversation_id = $1`,
      [access.conversationId]
    );
    const users = new Set(result.rows.map((row) => row.user_id));
    users.add(actorUserId);
    return [...users];
  }

  private async conversation(
    client: QueryExecutor,
    conversationId: string,
    lock: boolean
  ): Promise<ConversationRow> {
    const result = await client.query<ConversationRow>(
      `SELECT id, type, latest_sequence, status
         FROM conversations
        WHERE id = $1
        ${lock ? "FOR UPDATE" : ""}`,
      [conversationId]
    );
    const row = result.rows[0];
    if (!row) {
      throw new ConversationDomainError(
        "CONVERSATION_NOT_FOUND",
        "会话不存在",
        404
      );
    }
    return row;
  }

  private async authorizeDirect(
    client: QueryExecutor,
    input: { userId: string; conversationId: string },
    conversation: ConversationRow
  ): Promise<ConversationAccess> {
    const result = await client.query<DirectAccessRow>(
      `SELECT f.status AS friendship_status,
              CASE WHEN dc.user_low_id = $2
                   THEN dc.user_high_id ELSE dc.user_low_id END AS other_user_id,
              COALESCE(setting.notification_override, 'inherit')
                AS notification_override,
              EXISTS (
                SELECT 1 FROM block_relations block
                 WHERE block.removed_at IS NULL
                   AND (
                     (block.blocker_user_id = dc.user_low_id
                       AND block.blocked_user_id = dc.user_high_id)
                     OR
                     (block.blocker_user_id = dc.user_high_id
                       AND block.blocked_user_id = dc.user_low_id)
                   )
              ) AS blocked
         FROM direct_conversations dc
         JOIN friendships f ON f.id = dc.friendship_id
         LEFT JOIN conversation_notification_settings setting
           ON setting.conversation_id = dc.conversation_id
          AND setting.user_id = $2
        WHERE dc.conversation_id = $1
          AND (dc.user_low_id = $2 OR dc.user_high_id = $2)`,
      [input.conversationId, input.userId]
    );
    const row = result.rows[0];
    if (!row) {
      throw new ConversationDomainError(
        "CONVERSATION_NOT_FOUND",
        "会话不存在",
        404
      );
    }
    const canSend =
      conversation.status === "active" &&
      row.friendship_status === "active" &&
      !row.blocked;
    return {
      conversationId: conversation.id,
      type: "direct",
      latestSequence: Number(conversation.latest_sequence),
      notificationMode:
        row.notification_override === "muted" ? "muted" : "normal",
      navigationKey: "friends",
      currentRole: row.blocked
        ? "blocked"
        : row.friendship_status === "active"
          ? "friend"
          : "formerFriend",
      canViewHistory: true,
      canSendMessage: canSend,
      peerUserId: row.other_user_id
    };
  }

  private async authorizePlaza(
    client: QueryExecutor,
    input: {
      userId: string;
      conversationId: string;
      capability: "view" | "send" | "read";
      locationContextToken?: string;
    },
    conversation: ConversationRow
  ): Promise<ConversationAccess> {
    const result = await client.query<PlazaAccessRow>(
      `SELECT grid.id AS plaza_id,
              EXISTS (
                SELECT 1 FROM user_plaza_anchors anchor
                 WHERE anchor.user_id = $2
                   AND anchor.grid_version_id = grid.grid_version_id
                   AND grid.id = ANY(anchor.plaza_ids)
              ) AS current_eligible,
              EXISTS (
                SELECT 1 FROM user_chat_history_entries history
                 WHERE history.user_id = $2
                   AND history.conversation_id = $1
              ) AS has_history,
              CASE
                WHEN setting.notification_override = 'normal' THEN 'normal'
                WHEN setting.notification_override = 'muted' THEN 'muted'
                WHEN COALESCE(privacy.global_group_muted, false) THEN 'muted'
                ELSE 'normal'
              END AS notification_mode
         FROM plaza_grids grid
         LEFT JOIN user_privacy_settings privacy ON privacy.user_id = $2
         LEFT JOIN conversation_notification_settings setting
           ON setting.conversation_id = grid.conversation_id
          AND setting.user_id = $2
        WHERE grid.conversation_id = $1
          AND grid.status = 'active'`,
      [input.conversationId, input.userId]
    );
    const row = result.rows[0];
    if (!row || conversation.status !== "active") {
      throw new ConversationDomainError(
        "PLAZA_CONVERSATION_UNAVAILABLE",
        "广场会话暂不可用",
        404
      );
    }
    if (!row.current_eligible && !row.has_history) {
      throw new ConversationDomainError(
        "PLAZA_VIEW_NOT_ALLOWED",
        "当前没有查看此广场记录的资格",
        403
      );
    }
    if (input.capability === "send") {
      if (!row.current_eligible || !input.locationContextToken?.trim()) {
        throw new ConversationDomainError(
          "PLAZA_LOCATION_CONTEXT_REQUIRED",
          "请刷新位置后再发送消息",
          403
        );
      }
      try {
        const snapshot = await this.locationContexts.resolve({
          token: input.locationContextToken,
          userId: input.userId,
          now: new Date()
        });
        if (!snapshot.authorizedPlazaIds?.includes(row.plaza_id)) {
          throw new ConversationDomainError(
            "PLAZA_LOCATION_NOT_AUTHORIZED",
            "当前位置不能在此广场发言",
            403
          );
        }
      } catch (error) {
        if (error instanceof ConversationDomainError) throw error;
        if (error instanceof LocationContextError) {
          throw new ConversationDomainError(
            error.code,
            error.message,
            error.status === 401 ? 403 : error.status
          );
        }
        throw error;
      }
    }
    return {
      conversationId: conversation.id,
      type: "plaza",
      latestSequence: Number(conversation.latest_sequence),
      notificationMode: row.notification_mode,
      navigationKey: "plaza",
      currentRole: row.current_eligible ? "nearby" : "history",
      canViewHistory: true,
      canSendMessage: row.current_eligible && input.capability === "send",
      peerUserId: null
    };
  }
}
