import { Injectable } from "@nestjs/common";
import { randomUUID } from "node:crypto";
import { DatabaseService } from "../database/database.service.js";
import type { QueryExecutor } from "../database/database.types.js";
import {
  ConversationDomainError,
  type ConversationDetail,
  type ConversationSummary,
  type MessageView,
  type ReadCursorView,
  type RealtimeConversationState,
  type UnreadState
} from "./conversation.types.js";

type MessageRow = {
  id: string;
  client_message_id: string | null;
  conversation_id: string;
  sequence: string | number;
  sender_user_id: string | null;
  sender_name: string | null;
  type: "text";
  body_text: string | null;
  payload: Record<string, unknown> | null;
  reply_to_message_id: string | null;
  send_status: string;
  created_at: Date;
  expires_at: Date | null;
  deleted_at: Date | null;
};

type ConversationRow = {
  conversation_id: string;
  latest_sequence: string | number;
  conversation_status: string;
  friendship_status: "active" | "deleted";
  other_user_id: string;
  other_nickname: string;
  remark_name: string | null;
  pinned: boolean;
  notification_override: "inherit" | "normal" | "muted";
  blocked: boolean;
  last_message_id: string | null;
  last_message_sequence: string | number | null;
  last_message_preview: string | null;
  last_message_created_at: Date | null;
  conversation_created_at: Date;
};

type ParticipantRow = {
  latest_sequence: string | number;
  conversation_status: string;
  friendship_id: string;
  friendship_status: "active" | "deleted";
  user_low_id: string;
  user_high_id: string;
  other_user_id: string;
  blocked: boolean;
};

function number(value: string | number | null): number {
  return value === null ? 0 : Number(value);
}

function messageView(row: MessageRow, now = new Date()): MessageView {
  const expired = row.expires_at !== null && row.expires_at <= now;
  return {
    messageId: row.id,
    clientMessageId: row.client_message_id,
    conversationId: row.conversation_id,
    sequence: number(row.sequence),
    sender:
      row.sender_user_id && row.sender_name
        ? {
            userId: row.sender_user_id,
            displayName: row.sender_name,
            avatar: null
          }
        : null,
    type: "text",
    text: row.deleted_at || expired ? null : row.body_text,
    payload: row.deleted_at || expired ? null : row.payload,
    media: [],
    replyToMessageId: row.reply_to_message_id,
    mentions: [],
    deliveryState: row.deleted_at
      ? "deleted"
      : expired
        ? "expired"
        : row.send_status === "sent"
          ? "sent"
          : "failed",
    createdAt: row.created_at.toISOString(),
    expiresAt: row.expires_at?.toISOString() ?? null
  };
}

@Injectable()
export class ConversationRepository {
  constructor(private readonly database: DatabaseService) {}

  async listConversations(input: {
    userId: string;
    offset: number;
    limit: number;
  }): Promise<{
    items: ConversationSummary[];
    hasMore: boolean;
    navigationUnread: number;
  }> {
    const result = await this.database.query<ConversationRow>(
      `${this.conversationSelect("$1")}
        WHERE (dc.user_low_id = $1 OR dc.user_high_id = $1)
          AND f.status = 'active'
          AND NOT EXISTS (
            SELECT 1 FROM block_relations br
             WHERE br.removed_at IS NULL
               AND (
                 (br.blocker_user_id = dc.user_low_id
                   AND br.blocked_user_id = dc.user_high_id)
                 OR
                 (br.blocker_user_id = dc.user_high_id
                   AND br.blocked_user_id = dc.user_low_id)
               )
          )
        ORDER BY COALESCE(fs.pinned, false) DESC,
                 COALESCE(last_message.created_at, c.created_at) DESC,
                 c.id DESC
        LIMIT $2 OFFSET $3`,
      [input.userId, input.limit + 1, input.offset]
    );
    const rows = result.rows.slice(0, input.limit);
    const items = await Promise.all(
      rows.map(async (row) =>
        this.summary(
          row,
          await this.unreadState(
            this.database,
            row.conversation_id,
            input.userId,
            row.notification_override
          ),
          true
        )
      )
    );
    return {
      items,
      hasMore: result.rows.length > input.limit,
      navigationUnread: await this.navigationUnread(input.userId)
    };
  }

  async getConversation(
    userId: string,
    conversationId: string
  ): Promise<ConversationDetail> {
    const result = await this.database.query<ConversationRow>(
      `${this.conversationSelect("$2")}
        WHERE c.id = $1
          AND (dc.user_low_id = $2 OR dc.user_high_id = $2)`,
      [conversationId, userId]
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
      row.conversation_status === "active" &&
      row.friendship_status === "active" &&
      !row.blocked;
    const summary = this.summary(
      row,
      await this.unreadState(
        this.database,
        conversationId,
        userId,
        row.notification_override
      ),
      canSend
    );
    return {
      ...summary,
      latestSequence: number(row.latest_sequence),
      currentRole: row.blocked
        ? "blocked"
        : row.friendship_status === "active"
          ? "friend"
          : "formerFriend",
      rules: { canViewHistory: true, canSendMessage: canSend },
      announcement: null
    };
  }

  async sendTextMessage(input: {
    userId: string;
    conversationId: string;
    clientMessageId: string;
    text: string;
    replyToMessageId: string | null;
    now: Date;
  }): Promise<{ message: MessageView; created: boolean }> {
    return this.database.transaction(async (client) => {
      const participant = await this.requireParticipant(
        client,
        input.userId,
        input.conversationId,
        true
      );
      const existing = await client.query<MessageRow>(
        `${this.messageSelect()}
          WHERE m.sender_user_id = $1 AND m.client_message_id = $2`,
        [input.userId, input.clientMessageId]
      );
      if (existing.rows[0]) {
        if (existing.rows[0].conversation_id !== input.conversationId) {
          throw new ConversationDomainError(
            "CLIENT_MESSAGE_ID_CONFLICT",
            "客户端消息标识已用于其他会话",
            409
          );
        }
        return {
          message: messageView(existing.rows[0], input.now),
          created: false
        };
      }
      if (participant.blocked) {
        throw new ConversationDomainError(
          "DIRECT_MESSAGE_BLOCKED",
          "当前关系不允许发送消息",
          403
        );
      }
      if (
        participant.conversation_status !== "active" ||
        participant.friendship_status !== "active"
      ) {
        throw new ConversationDomainError(
          "DIRECT_MESSAGE_REQUIRES_FRIEND",
          "只有好友可以发送私聊消息",
          403
        );
      }
      if (input.replyToMessageId) {
        const reply = await client.query(
          `SELECT 1 FROM messages
            WHERE id = $1 AND conversation_id = $2`,
          [input.replyToMessageId, input.conversationId]
        );
        if (!reply.rowCount) {
          throw new ConversationDomainError(
            "REPLY_MESSAGE_NOT_FOUND",
            "回复的消息不存在",
            404
          );
        }
      }

      const sequenceResult = await client.query<{ latest_sequence: string | number }>(
        `UPDATE conversations
            SET latest_sequence = latest_sequence + 1,
                updated_at = $2
          WHERE id = $1
          RETURNING latest_sequence`,
        [input.conversationId, input.now]
      );
      const sequence = number(sequenceResult.rows[0].latest_sequence);
      const messageId = randomUUID();
      await client.query(
        `INSERT INTO messages (
           id, conversation_id, sequence, sender_user_id, client_message_id,
           type, body_text, reply_to_message_id, retention_policy, expires_at,
           send_status, created_at
         ) VALUES (
           $1, $2, $3, $4, $5, 'text', $6, $7,
           'direct_text_6m',
           $8::timestamptz + interval '6 months',
           'sent',
           $8::timestamptz
         )`,
        [
          messageId,
          input.conversationId,
          sequence,
          input.userId,
          input.clientMessageId,
          input.text,
          input.replyToMessageId,
          input.now
        ]
      );
      await client.query(
        `INSERT INTO conversation_read_cursors (
           conversation_id, user_id, last_read_sequence,
           first_unread_sequence, updated_at
         ) VALUES ($1, $2, 0, $3, $4)
         ON CONFLICT (conversation_id, user_id) DO UPDATE
           SET first_unread_sequence = COALESCE(
                 conversation_read_cursors.first_unread_sequence,
                 EXCLUDED.first_unread_sequence
               ),
               updated_at = EXCLUDED.updated_at`,
        [
          input.conversationId,
          participant.other_user_id,
          sequence,
          input.now
        ]
      );
      return {
        message: await this.getMessage(client, messageId),
        created: true
      };
    });
  }

  async participantUserIds(
    userId: string,
    conversationId: string
  ): Promise<string[]> {
    const participant = await this.requireParticipant(
      this.database,
      userId,
      conversationId,
      false
    );
    return [participant.user_low_id, participant.user_high_id];
  }

  async realtimeConversationState(
    userId: string,
    conversationId: string
  ): Promise<RealtimeConversationState> {
    const conversation = await this.getConversation(userId, conversationId);
    return {
      conversationId,
      unread: conversation.unread,
      navigationUnreadCount: await this.navigationUnread(userId)
    };
  }

  async listMessages(input: {
    userId: string;
    conversationId: string;
    beforeSequence?: number;
    afterSequence?: number;
    anchorSequence?: number;
    limit: number;
  }): Promise<{
    items: MessageView[];
    hasEarlier: boolean;
    hasLater: boolean;
  }> {
    await this.requireParticipant(
      this.database,
      input.userId,
      input.conversationId,
      false
    );
    let rows: MessageRow[];
    if (input.anchorSequence !== undefined) {
      const anchorExists = await this.database.query(
        `SELECT 1 FROM messages
          WHERE conversation_id = $1 AND sequence = $2`,
        [input.conversationId, input.anchorSequence]
      );
      if (!anchorExists.rowCount) {
        throw new ConversationDomainError(
          "MESSAGE_ANCHOR_NOT_FOUND",
          "定位的消息不存在",
          404
        );
      }
      const before = await this.database.query<MessageRow>(
        `${this.messageSelect()}
          WHERE m.conversation_id = $1 AND m.sequence <= $2
          ORDER BY m.sequence DESC LIMIT $3`,
        [input.conversationId, input.anchorSequence, input.limit]
      );
      const after = await this.database.query<MessageRow>(
        `${this.messageSelect()}
          WHERE m.conversation_id = $1 AND m.sequence > $2
          ORDER BY m.sequence ASC LIMIT $3`,
        [input.conversationId, input.anchorSequence, input.limit]
      );
      const desiredBefore = Math.ceil(input.limit / 2);
      const desiredAfter = input.limit - desiredBefore;
      let beforeTake = Math.min(desiredBefore, before.rows.length);
      let afterTake = Math.min(desiredAfter, after.rows.length);
      let remaining = input.limit - beforeTake - afterTake;
      const extraBefore = Math.min(
        remaining,
        before.rows.length - beforeTake
      );
      beforeTake += extraBefore;
      remaining -= extraBefore;
      afterTake += Math.min(remaining, after.rows.length - afterTake);
      rows = [
        ...before.rows.slice(0, beforeTake).reverse(),
        ...after.rows.slice(0, afterTake)
      ];
    } else if (input.beforeSequence !== undefined) {
      const result = await this.database.query<MessageRow>(
        `${this.messageSelect()}
          WHERE m.conversation_id = $1 AND m.sequence < $2
          ORDER BY m.sequence DESC LIMIT $3`,
        [input.conversationId, input.beforeSequence, input.limit]
      );
      rows = result.rows.reverse();
    } else if (input.afterSequence !== undefined) {
      const result = await this.database.query<MessageRow>(
        `${this.messageSelect()}
          WHERE m.conversation_id = $1 AND m.sequence > $2
          ORDER BY m.sequence ASC LIMIT $3`,
        [input.conversationId, input.afterSequence, input.limit]
      );
      rows = result.rows;
    } else {
      const result = await this.database.query<MessageRow>(
        `${this.messageSelect()}
          WHERE m.conversation_id = $1
          ORDER BY m.sequence DESC LIMIT $2`,
        [input.conversationId, input.limit]
      );
      rows = result.rows.reverse();
    }
    if (!rows.length) {
      return { items: [], hasEarlier: false, hasLater: false };
    }
    const first = number(rows[0].sequence);
    const last = number(rows.at(-1)!.sequence);
    const bounds = await this.database.query<{ earlier: boolean; later: boolean }>(
      `SELECT
         EXISTS (
           SELECT 1 FROM messages
            WHERE conversation_id = $1 AND sequence < $2
         ) AS earlier,
         EXISTS (
           SELECT 1 FROM messages
            WHERE conversation_id = $1 AND sequence > $3
         ) AS later`,
      [input.conversationId, first, last]
    );
    return {
      items: rows.map((row) => messageView(row)),
      hasEarlier: bounds.rows[0].earlier,
      hasLater: bounds.rows[0].later
    };
  }

  async advanceReadCursor(input: {
    userId: string;
    conversationId: string;
    lastReadSequence: number;
    now: Date;
  }): Promise<ReadCursorView> {
    return this.database.transaction(async (client) => {
      const participant = await this.requireParticipant(
        client,
        input.userId,
        input.conversationId,
        true
      );
      const latestSequence = number(participant.latest_sequence);
      if (input.lastReadSequence > latestSequence) {
        throw new ConversationDomainError(
          "READ_SEQUENCE_AHEAD",
          "已读序号不能超过会话最新消息",
          409
        );
      }
      const current = await client.query<{ last_read_sequence: string | number }>(
        `SELECT last_read_sequence
           FROM conversation_read_cursors
          WHERE conversation_id = $1 AND user_id = $2
          FOR UPDATE`,
        [input.conversationId, input.userId]
      );
      const previousSequence = number(
        current.rows[0]?.last_read_sequence ?? 0
      );
      const previousUnread = await this.unreadState(
        client,
        input.conversationId,
        input.userId,
        "normal",
        previousSequence
      );
      const resolvedSequence = Math.max(
        previousSequence,
        input.lastReadSequence
      );
      const unread = await this.unreadState(
        client,
        input.conversationId,
        input.userId,
        "normal",
        resolvedSequence
      );
      await client.query(
        `INSERT INTO conversation_read_cursors (
           conversation_id, user_id, last_read_sequence,
           first_unread_sequence, updated_at
         ) VALUES ($1, $2, $3, $4, $5)
         ON CONFLICT (conversation_id, user_id) DO UPDATE
           SET last_read_sequence = GREATEST(
                 conversation_read_cursors.last_read_sequence,
                 EXCLUDED.last_read_sequence
               ),
               first_unread_sequence = EXCLUDED.first_unread_sequence,
               updated_at = EXCLUDED.updated_at`,
        [
          input.conversationId,
          input.userId,
          resolvedSequence,
          unread.firstUnreadSequence,
          input.now
        ]
      );
      return {
        conversationId: input.conversationId,
        lastReadSequence: resolvedSequence,
        unread,
        navigationUnreadDelta: unread.count - previousUnread.count
      };
    });
  }

  private summary(
    row: ConversationRow,
    unread: UnreadState,
    canSend: boolean
  ): ConversationSummary {
    return {
      conversationId: row.conversation_id,
      type: "direct",
      title: row.remark_name ?? row.other_nickname,
      avatar: null,
      lastMessage: row.last_message_id
        ? {
            messageId: row.last_message_id,
            sequence: number(row.last_message_sequence),
            preview: row.last_message_preview ?? "",
            createdAt: row.last_message_created_at!.toISOString()
          }
        : null,
      unread,
      notificationMode:
        row.notification_override === "muted" ? "muted" : "normal",
      pinned: row.pinned,
      allowedActions: canSend
        ? ["viewMessages", "sendMessage", "markRead"]
        : ["viewMessages", "markRead"]
    };
  }

  private async unreadState(
    client: QueryExecutor,
    conversationId: string,
    userId: string,
    notificationOverride: "inherit" | "normal" | "muted",
    overrideCursor?: number
  ): Promise<UnreadState> {
    const result = await client.query<{
      unread_count: string | number;
      first_unread_sequence: string | number | null;
    }>(
      `SELECT count(*) AS unread_count, min(m.sequence) AS first_unread_sequence
         FROM messages m
        WHERE m.conversation_id = $1
          AND m.sender_user_id IS DISTINCT FROM $2
          AND m.deleted_at IS NULL
          AND (m.expires_at IS NULL OR m.expires_at > now())
          AND m.sequence > COALESCE(
            $3,
            (
              SELECT crc.last_read_sequence
                FROM conversation_read_cursors crc
               WHERE crc.conversation_id = $1 AND crc.user_id = $2
            ),
            0
          )`,
      [conversationId, userId, overrideCursor ?? null]
    );
    const count = number(result.rows[0].unread_count);
    return {
      count,
      appearance:
        count === 0
          ? "none"
          : notificationOverride === "muted"
            ? "gray"
            : "red",
      firstUnreadSequence:
        result.rows[0].first_unread_sequence === null
          ? null
          : number(result.rows[0].first_unread_sequence)
    };
  }

  private async navigationUnread(userId: string): Promise<number> {
    const result = await this.database.query<{ unread_count: string | number }>(
      `SELECT count(*) AS unread_count
         FROM messages m
         JOIN direct_conversations dc ON dc.conversation_id = m.conversation_id
         JOIN friendships f ON f.id = dc.friendship_id
         LEFT JOIN conversation_read_cursors crc
           ON crc.conversation_id = m.conversation_id AND crc.user_id = $1
         LEFT JOIN conversation_notification_settings cns
           ON cns.conversation_id = m.conversation_id AND cns.user_id = $1
        WHERE (dc.user_low_id = $1 OR dc.user_high_id = $1)
          AND f.status = 'active'
          AND m.sender_user_id IS DISTINCT FROM $1
          AND m.sequence > COALESCE(crc.last_read_sequence, 0)
          AND m.deleted_at IS NULL
          AND (m.expires_at IS NULL OR m.expires_at > now())
          AND COALESCE(cns.notification_override, 'inherit') <> 'muted'
          AND NOT EXISTS (
            SELECT 1 FROM block_relations br
             WHERE br.removed_at IS NULL
               AND (
                 (br.blocker_user_id = dc.user_low_id
                   AND br.blocked_user_id = dc.user_high_id)
                 OR
                 (br.blocker_user_id = dc.user_high_id
                   AND br.blocked_user_id = dc.user_low_id)
               )
          )`,
      [userId]
    );
    return number(result.rows[0].unread_count);
  }

  private async requireParticipant(
    client: QueryExecutor,
    userId: string,
    conversationId: string,
    lockConversation: boolean
  ): Promise<ParticipantRow> {
    const result = await client.query<ParticipantRow>(
      `SELECT c.latest_sequence, c.status AS conversation_status,
              f.id AS friendship_id, f.status AS friendship_status,
              dc.user_low_id, dc.user_high_id,
              CASE WHEN dc.user_low_id = $2
                   THEN dc.user_high_id ELSE dc.user_low_id END AS other_user_id,
              EXISTS (
                SELECT 1 FROM block_relations br
                 WHERE br.removed_at IS NULL
                   AND (
                     (br.blocker_user_id = dc.user_low_id
                       AND br.blocked_user_id = dc.user_high_id)
                     OR
                     (br.blocker_user_id = dc.user_high_id
                       AND br.blocked_user_id = dc.user_low_id)
                   )
              ) AS blocked
         FROM conversations c
         JOIN direct_conversations dc ON dc.conversation_id = c.id
         JOIN friendships f ON f.id = dc.friendship_id
        WHERE c.id = $1
          AND (dc.user_low_id = $2 OR dc.user_high_id = $2)
        ${lockConversation ? "FOR UPDATE OF c" : ""}`,
      [conversationId, userId]
    );
    if (!result.rows[0]) {
      throw new ConversationDomainError(
        "CONVERSATION_NOT_FOUND",
        "会话不存在",
        404
      );
    }
    return result.rows[0];
  }

  private async getMessage(
    client: QueryExecutor,
    messageId: string
  ): Promise<MessageView> {
    const result = await client.query<MessageRow>(
      `${this.messageSelect()} WHERE m.id = $1`,
      [messageId]
    );
    if (!result.rows[0]) {
      throw new ConversationDomainError("MESSAGE_NOT_FOUND", "消息不存在", 404);
    }
    return messageView(result.rows[0]);
  }

  private messageSelect(): string {
    return `SELECT m.id, m.client_message_id, m.conversation_id, m.sequence,
                   m.sender_user_id, up.nickname AS sender_name, m.type,
                   m.body_text, m.payload, m.reply_to_message_id,
                   m.send_status, m.created_at, m.expires_at, m.deleted_at
              FROM messages m
              LEFT JOIN user_profiles up ON up.user_id = m.sender_user_id`;
  }

  private conversationSelect(userParameter: string): string {
    return `SELECT c.id AS conversation_id, c.latest_sequence,
                   c.status AS conversation_status,
                   f.status AS friendship_status,
                   other_user.id AS other_user_id,
                   up.nickname AS other_nickname,
                   fs.remark_name,
                   COALESCE(fs.pinned, false) AS pinned,
                   COALESCE(cns.notification_override, 'inherit')
                     AS notification_override,
                   EXISTS (
                     SELECT 1 FROM block_relations active_block
                      WHERE active_block.removed_at IS NULL
                        AND (
                          (active_block.blocker_user_id = dc.user_low_id
                            AND active_block.blocked_user_id = dc.user_high_id)
                          OR
                          (active_block.blocker_user_id = dc.user_high_id
                            AND active_block.blocked_user_id = dc.user_low_id)
                        )
                   ) AS blocked,
                   last_message.id AS last_message_id,
                   last_message.sequence AS last_message_sequence,
                   CASE last_message.type
                     WHEN 'text' THEN last_message.body_text
                     WHEN 'image' THEN '[图片]'
                     WHEN 'voice' THEN '[语音]'
                     WHEN 'video' THEN '[视频]'
                     WHEN 'sticker' THEN '[表情]'
                     ELSE '[消息]'
                   END AS last_message_preview,
                   last_message.created_at AS last_message_created_at,
                   c.created_at AS conversation_created_at
              FROM conversations c
              JOIN direct_conversations dc ON dc.conversation_id = c.id
              JOIN friendships f ON f.id = dc.friendship_id
              JOIN users other_user
                ON other_user.id = CASE
                  WHEN dc.user_low_id = ${userParameter} THEN dc.user_high_id
                  ELSE dc.user_low_id
                END
              JOIN user_profiles up ON up.user_id = other_user.id
              LEFT JOIN friend_settings fs
                ON fs.friendship_id = f.id
               AND fs.owner_user_id = ${userParameter}
              LEFT JOIN conversation_notification_settings cns
                ON cns.conversation_id = c.id
               AND cns.user_id = ${userParameter}
              LEFT JOIN LATERAL (
                SELECT latest.id, latest.sequence, latest.type,
                       latest.body_text, latest.created_at
                  FROM messages latest
                 WHERE latest.conversation_id = c.id
                   AND latest.deleted_at IS NULL
                   AND (latest.expires_at IS NULL OR latest.expires_at > now())
                 ORDER BY latest.sequence DESC
                 LIMIT 1
              ) last_message ON true`;
  }

}
