import { Injectable } from "@nestjs/common";
import { randomUUID } from "node:crypto";
import { DatabaseService } from "../database/database.service.js";
import type { QueryExecutor } from "../database/database.types.js";
import {
  RelationshipDomainError,
  type BlockView,
  type FriendDecisionView,
  type FriendRequestView,
  type FriendView,
  type UserSummary
} from "./relationship.types.js";

type RequestRow = {
  id: string;
  sender_user_id: string;
  sender_name: string;
  receiver_user_id: string;
  receiver_name: string;
  status: FriendRequestView["status"];
  application_note: string;
  created_at: Date;
  decided_at: Date | null;
};

function pair(userA: string, userB: string): [string, string] {
  return userA < userB ? [userA, userB] : [userB, userA];
}

function userSummary(id: string, displayName: string): UserSummary {
  return { userId: id, displayName, avatar: null };
}

function requestView(row: RequestRow): FriendRequestView {
  return {
    requestId: row.id,
    sender: userSummary(row.sender_user_id, row.sender_name),
    receiver: userSummary(row.receiver_user_id, row.receiver_name),
    status: row.status,
    applicationNote: row.application_note,
    createdAt: row.created_at.toISOString(),
    decidedAt: row.decided_at?.toISOString() ?? null
  };
}

@Injectable()
export class RelationshipRepository {
  constructor(private readonly database: DatabaseService) {}

  async createRequest(input: {
    senderUserId: string;
    targetUserId: string;
    applicationNote: string;
    idempotencyKeyHash: string;
    now: Date;
  }): Promise<FriendRequestView> {
    return this.database.transaction(async (client) => {
      if (input.senderUserId === input.targetUserId) {
        throw new RelationshipDomainError(
          "FRIEND_REQUEST_SELF",
          "不能添加自己为好友",
          422
        );
      }

      const retried = await client.query<RequestRow>(
        `${this.requestSelect()}
          WHERE fr.sender_user_id = $1
            AND fr.create_idempotency_key_hash = $2`,
        [input.senderUserId, input.idempotencyKeyHash]
      );
      if (retried.rows[0]) {
        return requestView(retried.rows[0]);
      }

      await this.lockPair(client, input.senderUserId, input.targetUserId);
      await this.requireActiveUser(client, input.targetUserId);
      await this.requireNotBlocked(client, input.senderUserId, input.targetUserId);

      const [low, high] = pair(input.senderUserId, input.targetUserId);
      const friendship = await client.query(
        `SELECT 1
           FROM friendships
          WHERE user_low_id = $1 AND user_high_id = $2 AND status = 'active'`,
        [low, high]
      );
      if (friendship.rowCount) {
        throw new RelationshipDomainError(
          "FRIENDSHIP_ALREADY_ACTIVE",
          "你们已经是好友",
          409
        );
      }

      const pending = await client.query(
        `SELECT 1
           FROM friend_requests
          WHERE status = 'pending'
            AND (
              (sender_user_id = $1 AND receiver_user_id = $2)
              OR (sender_user_id = $2 AND receiver_user_id = $1)
            )`,
        [input.senderUserId, input.targetUserId]
      );
      if (pending.rowCount) {
        throw new RelationshipDomainError(
          "FRIEND_REQUEST_ALREADY_PENDING",
          "已有待处理的好友申请",
          409
        );
      }

      const requestId = randomUUID();
      await client.query(
        `INSERT INTO friend_requests (
           id, sender_user_id, receiver_user_id, application_note, status,
           create_idempotency_key_hash, created_at, updated_at
         ) VALUES ($1, $2, $3, $4, 'pending', $5, $6, $6)`,
        [
          requestId,
          input.senderUserId,
          input.targetUserId,
          input.applicationNote,
          input.idempotencyKeyHash,
          input.now
        ]
      );
      await this.audit(client, {
        actorUserId: input.senderUserId,
        targetUserId: input.targetUserId,
        action: "friend_request_created",
        requestId,
        now: input.now
      });
      return this.getRequest(client, requestId);
    });
  }

  async listRequests(input: {
    userId: string;
    direction: "received" | "sent" | "all";
    status: "pending" | "accepted" | "rejected" | "all";
    offset: number;
    limit: number;
  }): Promise<{ items: FriendRequestView[]; hasMore: boolean }> {
    const values: unknown[] = [input.userId];
    const conditions: string[] = [];
    if (input.direction === "received") {
      conditions.push("fr.receiver_user_id = $1");
    } else if (input.direction === "sent") {
      conditions.push("fr.sender_user_id = $1");
    } else {
      conditions.push("(fr.sender_user_id = $1 OR fr.receiver_user_id = $1)");
    }
    if (input.status !== "all") {
      values.push(input.status);
      conditions.push(`fr.status = $${values.length}`);
    }
    values.push(input.limit + 1, input.offset);
    const result = await this.database.query<RequestRow>(
      `${this.requestSelect()}
        WHERE ${conditions.join(" AND ")}
        ORDER BY CASE WHEN fr.status = 'pending' THEN 0 ELSE 1 END,
                 fr.created_at DESC, fr.id DESC
        LIMIT $${values.length - 1} OFFSET $${values.length}`,
      values
    );
    return {
      items: result.rows.slice(0, input.limit).map(requestView),
      hasMore: result.rows.length > input.limit
    };
  }

  async decideRequest(input: {
    requestId: string;
    receiverUserId: string;
    decision: "accept" | "reject";
    now: Date;
  }): Promise<FriendDecisionView> {
    return this.database.transaction(async (client) => {
      const locked = await client.query<{
        sender_user_id: string;
        receiver_user_id: string;
        status: FriendRequestView["status"];
      }>(
        `SELECT sender_user_id, receiver_user_id, status
           FROM friend_requests
          WHERE id = $1
          FOR UPDATE`,
        [input.requestId]
      );
      const request = locked.rows[0];
      if (!request) {
        throw new RelationshipDomainError(
          "FRIEND_REQUEST_NOT_FOUND",
          "好友申请不存在",
          404
        );
      }
      if (request.receiver_user_id !== input.receiverUserId) {
        throw new RelationshipDomainError(
          "FRIEND_REQUEST_FORBIDDEN",
          "只有接收方可以处理申请",
          403
        );
      }

      const expectedStatus = input.decision === "accept" ? "accepted" : "rejected";
      if (request.status !== "pending") {
        if (request.status === expectedStatus) {
          return this.decisionView(client, input.requestId, request);
        }
        throw new RelationshipDomainError(
          "FRIEND_REQUEST_ALREADY_DECIDED",
          "好友申请已经处理",
          409
        );
      }

      if (input.decision === "reject") {
        await client.query(
          `UPDATE friend_requests
              SET status = 'rejected', decided_at = $2, updated_at = $2
            WHERE id = $1`,
          [input.requestId, input.now]
        );
        await this.audit(client, {
          actorUserId: input.receiverUserId,
          targetUserId: request.sender_user_id,
          action: "friend_request_rejected",
          requestId: input.requestId,
          now: input.now
        });
        return this.decisionView(client, input.requestId, {
          ...request,
          status: "rejected"
        });
      }

      await this.lockPair(client, request.sender_user_id, request.receiver_user_id);
      await this.requireNotBlocked(
        client,
        request.sender_user_id,
        request.receiver_user_id
      );
      const [low, high] = pair(request.sender_user_id, request.receiver_user_id);
      const friendshipId = randomUUID();
      const friendship = await client.query<{ id: string }>(
        `INSERT INTO friendships (
           id, user_low_id, user_high_id, status, established_from_request_id,
           created_at, updated_at
         ) VALUES ($1, $2, $3, 'active', $4, $5, $5)
         ON CONFLICT (user_low_id, user_high_id) DO UPDATE
           SET status = 'active',
               established_from_request_id = EXCLUDED.established_from_request_id,
               updated_at = EXCLUDED.updated_at
         RETURNING id`,
        [friendshipId, low, high, input.requestId, input.now]
      );
      const resolvedFriendshipId = friendship.rows[0].id;
      await client.query(
        `INSERT INTO friend_settings (
           friendship_id, owner_user_id, updated_at
         ) VALUES ($1, $2, $4), ($1, $3, $4)
         ON CONFLICT (friendship_id, owner_user_id) DO NOTHING`,
        [resolvedFriendshipId, low, high, input.now]
      );

      let conversationId: string;
      const existingConversation = await client.query<{ conversation_id: string }>(
        `SELECT conversation_id
           FROM direct_conversations
          WHERE friendship_id = $1`,
        [resolvedFriendshipId]
      );
      if (existingConversation.rows[0]) {
        conversationId = existingConversation.rows[0].conversation_id;
        await client.query(
          `UPDATE conversations
              SET status = 'active', updated_at = $2
            WHERE id = $1`,
          [conversationId, input.now]
        );
      } else {
        conversationId = randomUUID();
        await client.query(
          `INSERT INTO conversations (id, type, status, created_at, updated_at)
           VALUES ($1, 'direct', 'active', $2, $2)`,
          [conversationId, input.now]
        );
        await client.query(
          `INSERT INTO direct_conversations (
             conversation_id, friendship_id, user_low_id, user_high_id, created_at
           ) VALUES ($1, $2, $3, $4, $5)`,
          [conversationId, resolvedFriendshipId, low, high, input.now]
        );
      }

      await client.query(
        `UPDATE friend_requests
            SET status = 'accepted', decided_at = $2, updated_at = $2
          WHERE id = $1`,
        [input.requestId, input.now]
      );
      await this.audit(client, {
        actorUserId: input.receiverUserId,
        targetUserId: request.sender_user_id,
        action: "friend_request_accepted",
        requestId: input.requestId,
        friendshipId: resolvedFriendshipId,
        now: input.now
      });
      return {
        request: await this.getRequest(client, input.requestId),
        friendshipId: resolvedFriendshipId,
        friendUserId: request.sender_user_id,
        directConversationId: conversationId
      };
    });
  }

  async listFriends(input: {
    userId: string;
    keyword?: string;
    offset: number;
    limit: number;
  }): Promise<{ items: FriendView[]; hasMore: boolean }> {
    const values: unknown[] = [input.userId];
    let keywordCondition = "";
    if (input.keyword) {
      values.push(`%${input.keyword}%`);
      keywordCondition =
        `AND (up.nickname ILIKE $${values.length} OR fs.remark_name ILIKE $${values.length})`;
    }
    values.push(input.limit + 1, input.offset);
    const result = await this.database.query<{
      user_id: string;
      nickname: string;
      remark_name: string | null;
      can_view_owner_posts: boolean;
      pinned: boolean;
      conversation_id: string;
      updated_at: Date;
    }>(
      `SELECT other_user.id AS user_id, up.nickname, fs.remark_name,
              fs.can_view_owner_posts, fs.pinned, dc.conversation_id,
              GREATEST(f.updated_at, fs.updated_at) AS updated_at
         FROM friendships f
         JOIN users other_user
           ON other_user.id = CASE
             WHEN f.user_low_id = $1 THEN f.user_high_id
             ELSE f.user_low_id
           END
         JOIN user_profiles up ON up.user_id = other_user.id
         JOIN friend_settings fs
           ON fs.friendship_id = f.id AND fs.owner_user_id = $1
         JOIN direct_conversations dc ON dc.friendship_id = f.id
        WHERE f.status = 'active'
          AND (f.user_low_id = $1 OR f.user_high_id = $1)
          ${keywordCondition}
        ORDER BY fs.pinned DESC, COALESCE(fs.remark_name, up.nickname), other_user.id
        LIMIT $${values.length - 1} OFFSET $${values.length}`,
      values
    );
    return {
      items: result.rows.slice(0, input.limit).map((row) => ({
        ...userSummary(row.user_id, row.remark_name ?? row.nickname),
        nickname: row.nickname,
        remarkName: row.remark_name,
        canViewMyPosts: row.can_view_owner_posts,
        pinned: row.pinned,
        directConversationId: row.conversation_id,
        updatedAt: row.updated_at.toISOString()
      })),
      hasMore: result.rows.length > input.limit
    };
  }

  async updateFriendSettings(input: {
    ownerUserId: string;
    friendUserId: string;
    remarkName?: string | null;
    canViewMyPosts?: boolean;
    pinned?: boolean;
    now: Date;
  }): Promise<{
    friendUserId: string;
    remarkName: string | null;
    canViewMyPosts: boolean;
    pinned: boolean;
    updatedAt: string;
  }> {
    const [low, high] = pair(input.ownerUserId, input.friendUserId);
    const friendship = await this.database.query<{ id: string }>(
      `SELECT id FROM friendships
        WHERE user_low_id = $1 AND user_high_id = $2 AND status = 'active'`,
      [low, high]
    );
    if (!friendship.rows[0]) {
      throw new RelationshipDomainError("FRIENDSHIP_NOT_FOUND", "对方不是你的好友", 404);
    }
    const result = await this.database.query<{
      remark_name: string | null;
      can_view_owner_posts: boolean;
      pinned: boolean;
      updated_at: Date;
    }>(
      `UPDATE friend_settings
          SET remark_name = CASE WHEN $3 THEN $4 ELSE remark_name END,
              can_view_owner_posts = COALESCE($5, can_view_owner_posts),
              pinned = COALESCE($6, pinned),
              updated_at = $7
        WHERE friendship_id = $1 AND owner_user_id = $2
        RETURNING remark_name, can_view_owner_posts, pinned, updated_at`,
      [
        friendship.rows[0].id,
        input.ownerUserId,
        input.remarkName !== undefined,
        input.remarkName ?? null,
        input.canViewMyPosts ?? null,
        input.pinned ?? null,
        input.now
      ]
    );
    const row = result.rows[0];
    return {
      friendUserId: input.friendUserId,
      remarkName: row.remark_name,
      canViewMyPosts: row.can_view_owner_posts,
      pinned: row.pinned,
      updatedAt: row.updated_at.toISOString()
    };
  }

  async deleteFriend(userId: string, friendUserId: string, now: Date): Promise<void> {
    await this.database.transaction(async (client) => {
      await this.lockPair(client, userId, friendUserId);
      const [low, high] = pair(userId, friendUserId);
      const result = await client.query<{ id: string }>(
        `UPDATE friendships
            SET status = 'deleted', updated_at = $3
          WHERE user_low_id = $1 AND user_high_id = $2 AND status = 'active'
          RETURNING id`,
        [low, high, now]
      );
      if (!result.rows[0]) {
        return;
      }
      await this.audit(client, {
        actorUserId: userId,
        targetUserId: friendUserId,
        action: "friendship_deleted",
        friendshipId: result.rows[0].id,
        now
      });
    });
  }

  async block(input: {
    blockerUserId: string;
    targetUserId: string;
    reasonCode?: string;
    now: Date;
  }): Promise<BlockView> {
    return this.database.transaction(async (client) => {
      if (input.blockerUserId === input.targetUserId) {
        throw new RelationshipDomainError("BLOCK_SELF", "不能拉黑自己", 422);
      }
      await this.lockPair(client, input.blockerUserId, input.targetUserId);
      await this.requireActiveUser(client, input.targetUserId);

      const active = await client.query<{
        prior_relation: "friend" | "stranger";
        created_at: Date;
      }>(
        `SELECT prior_relation, created_at
           FROM block_relations
          WHERE blocker_user_id = $1 AND blocked_user_id = $2 AND removed_at IS NULL`,
        [input.blockerUserId, input.targetUserId]
      );
      if (active.rows[0]) {
        return this.blockView(
          client,
          input.blockerUserId,
          input.targetUserId,
          "blocked",
          active.rows[0].prior_relation,
          null,
          active.rows[0].created_at
        );
      }

      const [low, high] = pair(input.blockerUserId, input.targetUserId);
      const friendship = await client.query<{ id: string; status: string }>(
        `SELECT id, status FROM friendships
          WHERE user_low_id = $1 AND user_high_id = $2`,
        [low, high]
      );
      const reverse = await client.query<{
        prior_relation: "friend" | "stranger";
        prior_friendship_id: string | null;
      }>(
        `SELECT prior_relation, prior_friendship_id
           FROM block_relations
          WHERE blocker_user_id = $1
            AND blocked_user_id = $2
            AND removed_at IS NULL`,
        [input.targetUserId, input.blockerUserId]
      );
      const priorRelation =
        friendship.rows[0]?.status === "active" ||
        reverse.rows[0]?.prior_relation === "friend"
          ? "friend"
          : "stranger";
      const friendshipId =
        priorRelation === "friend"
          ? friendship.rows[0]?.id ?? reverse.rows[0]?.prior_friendship_id ?? null
          : null;
      await client.query(
        `INSERT INTO block_relations (
           blocker_user_id, blocked_user_id, prior_relation, prior_friendship_id,
           reason_code, created_at, removed_at
         ) VALUES ($1, $2, $3, $4, $5, $6, NULL)
         ON CONFLICT (blocker_user_id, blocked_user_id) DO UPDATE
           SET prior_relation = EXCLUDED.prior_relation,
               prior_friendship_id = EXCLUDED.prior_friendship_id,
               reason_code = EXCLUDED.reason_code,
               created_at = EXCLUDED.created_at,
               removed_at = NULL`,
        [
          input.blockerUserId,
          input.targetUserId,
          priorRelation,
          friendshipId,
          input.reasonCode ?? null,
          input.now
        ]
      );
      if (friendship.rows[0]?.status === "active" && friendshipId) {
        await client.query(
          `UPDATE friendships SET status = 'deleted', updated_at = $2 WHERE id = $1`,
          [friendshipId, input.now]
        );
      }
      await this.audit(client, {
        actorUserId: input.blockerUserId,
        targetUserId: input.targetUserId,
        action: "user_blocked",
        friendshipId: friendshipId ?? undefined,
        now: input.now,
        metadata: { priorRelation, reasonCode: input.reasonCode ?? null }
      });
      return this.blockView(
        client,
        input.blockerUserId,
        input.targetUserId,
        "blocked",
        priorRelation,
        null,
        input.now
      );
    });
  }

  async unblock(input: {
    blockerUserId: string;
    targetUserId: string;
    now: Date;
  }): Promise<BlockView> {
    return this.database.transaction(async (client) => {
      await this.lockPair(client, input.blockerUserId, input.targetUserId);
      const relation = await client.query<{
        prior_relation: "friend" | "stranger";
        prior_friendship_id: string | null;
        removed_at: Date | null;
      }>(
        `SELECT prior_relation, prior_friendship_id, removed_at
           FROM block_relations
          WHERE blocker_user_id = $1 AND blocked_user_id = $2
          FOR UPDATE`,
        [input.blockerUserId, input.targetUserId]
      );
      const row = relation.rows[0];
      if (!row) {
        throw new RelationshipDomainError("BLOCK_NOT_FOUND", "对方不在黑名单中", 404);
      }
      if (row.removed_at) {
        return this.blockView(
          client,
          input.blockerUserId,
          input.targetUserId,
          "unblocked",
          row.prior_relation,
          row.prior_relation,
          row.removed_at
        );
      }
      await client.query(
        `UPDATE block_relations
            SET removed_at = $3
          WHERE blocker_user_id = $1 AND blocked_user_id = $2`,
        [input.blockerUserId, input.targetUserId, input.now]
      );
      const reverseBlock = await client.query(
        `SELECT 1
           FROM block_relations
          WHERE blocker_user_id = $1
            AND blocked_user_id = $2
            AND removed_at IS NULL`,
        [input.targetUserId, input.blockerUserId]
      );
      if (
        row.prior_relation === "friend" &&
        row.prior_friendship_id &&
        reverseBlock.rowCount === 0
      ) {
        await client.query(
          `UPDATE friendships SET status = 'active', updated_at = $2 WHERE id = $1`,
          [row.prior_friendship_id, input.now]
        );
      }
      await this.audit(client, {
        actorUserId: input.blockerUserId,
        targetUserId: input.targetUserId,
        action: "user_unblocked",
        friendshipId: row.prior_friendship_id ?? undefined,
        now: input.now,
        metadata: { restoredRelation: row.prior_relation }
      });
      return this.blockView(
        client,
        input.blockerUserId,
        input.targetUserId,
        "unblocked",
        row.prior_relation,
        row.prior_relation,
        input.now
      );
    });
  }

  async listBlocks(input: {
    blockerUserId: string;
    offset: number;
    limit: number;
  }): Promise<{ items: BlockView[]; hasMore: boolean }> {
    const result = await this.database.query<{
      blocked_user_id: string;
      nickname: string;
      prior_relation: "friend" | "stranger";
      created_at: Date;
    }>(
      `SELECT br.blocked_user_id, up.nickname, br.prior_relation, br.created_at
         FROM block_relations br
         JOIN user_profiles up ON up.user_id = br.blocked_user_id
        WHERE br.blocker_user_id = $1 AND br.removed_at IS NULL
        ORDER BY br.created_at DESC
        LIMIT $2 OFFSET $3`,
      [input.blockerUserId, input.limit + 1, input.offset]
    );
    return {
      items: result.rows.slice(0, input.limit).map((row) => ({
        target: userSummary(row.blocked_user_id, row.nickname),
        state: "blocked",
        priorRelation: row.prior_relation,
        restoredRelation: null,
        directMessagingAllowed: false,
        updatedAt: row.created_at.toISOString()
      })),
      hasMore: result.rows.length > input.limit
    };
  }

  private async decisionView(
    client: QueryExecutor,
    requestId: string,
    request: {
      sender_user_id: string;
      receiver_user_id: string;
      status: FriendRequestView["status"];
    }
  ): Promise<FriendDecisionView> {
    if (request.status !== "accepted") {
      return {
        request: await this.getRequest(client, requestId),
        friendshipId: null,
        friendUserId: null,
        directConversationId: null
      };
    }
    const [low, high] = pair(request.sender_user_id, request.receiver_user_id);
    const result = await client.query<{
      friendship_id: string;
      conversation_id: string;
    }>(
      `SELECT f.id AS friendship_id, dc.conversation_id
         FROM friendships f
         JOIN direct_conversations dc ON dc.friendship_id = f.id
        WHERE f.user_low_id = $1 AND f.user_high_id = $2`,
      [low, high]
    );
    return {
      request: await this.getRequest(client, requestId),
      friendshipId: result.rows[0]?.friendship_id ?? null,
      friendUserId: request.sender_user_id,
      directConversationId: result.rows[0]?.conversation_id ?? null
    };
  }

  private async blockView(
    client: QueryExecutor,
    currentUserId: string,
    targetUserId: string,
    state: "blocked" | "unblocked",
    priorRelation: "friend" | "stranger",
    restoredRelation: "friend" | "stranger" | null,
    updatedAt: Date
  ): Promise<BlockView> {
    const target = await client.query<{ nickname: string }>(
      `SELECT nickname FROM user_profiles WHERE user_id = $1`,
      [targetUserId]
    );
    const reverseBlock = await client.query(
      `SELECT 1 FROM block_relations
        WHERE blocker_user_id = $1 AND blocked_user_id = $2 AND removed_at IS NULL`,
      [targetUserId, currentUserId]
    );
    return {
      target: userSummary(targetUserId, target.rows[0]?.nickname ?? "未知用户"),
      state,
      priorRelation,
      restoredRelation,
      directMessagingAllowed:
        state === "unblocked" && reverseBlock.rowCount === 0 && restoredRelation === "friend",
      updatedAt: updatedAt.toISOString()
    };
  }

  private requestSelect(): string {
    return `SELECT fr.id, fr.sender_user_id, sender.nickname AS sender_name,
                   fr.receiver_user_id, receiver.nickname AS receiver_name,
                   fr.status, fr.application_note, fr.created_at, fr.decided_at
              FROM friend_requests fr
              JOIN user_profiles sender ON sender.user_id = fr.sender_user_id
              JOIN user_profiles receiver ON receiver.user_id = fr.receiver_user_id`;
  }

  private async getRequest(
    client: QueryExecutor,
    requestId: string
  ): Promise<FriendRequestView> {
    const result = await client.query<RequestRow>(
      `${this.requestSelect()} WHERE fr.id = $1`,
      [requestId]
    );
    if (!result.rows[0]) {
      throw new RelationshipDomainError(
        "FRIEND_REQUEST_NOT_FOUND",
        "好友申请不存在",
        404
      );
    }
    return requestView(result.rows[0]);
  }

  private async requireActiveUser(client: QueryExecutor, userId: string): Promise<void> {
    const result = await client.query(
      `SELECT 1 FROM users WHERE id = $1 AND status = 'active' AND deleted_at IS NULL`,
      [userId]
    );
    if (!result.rowCount) {
      throw new RelationshipDomainError("USER_NOT_FOUND", "用户不存在", 404);
    }
  }

  private async requireNotBlocked(
    client: QueryExecutor,
    userA: string,
    userB: string
  ): Promise<void> {
    const result = await client.query(
      `SELECT 1
         FROM block_relations
        WHERE removed_at IS NULL
          AND (
            (blocker_user_id = $1 AND blocked_user_id = $2)
            OR (blocker_user_id = $2 AND blocked_user_id = $1)
          )`,
      [userA, userB]
    );
    if (result.rowCount) {
      throw new RelationshipDomainError(
        "BLOCK_RELATION_ACTIVE",
        "当前关系被拉黑限制",
        403
      );
    }
  }

  private async lockPair(client: QueryExecutor, userA: string, userB: string): Promise<void> {
    const [low, high] = pair(userA, userB);
    await client.query(`SELECT pg_advisory_xact_lock(hashtextextended($1, 0))`, [
      `${low}:${high}`
    ]);
  }

  private async audit(
    client: QueryExecutor,
    input: {
      actorUserId: string;
      targetUserId: string;
      action: string;
      requestId?: string;
      friendshipId?: string;
      metadata?: Record<string, unknown>;
      now: Date;
    }
  ): Promise<void> {
    await client.query(
      `INSERT INTO relationship_audit_logs (
         id, actor_user_id, target_user_id, action, friend_request_id,
         friendship_id, metadata, created_at
       ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
      [
        randomUUID(),
        input.actorUserId,
        input.targetUserId,
        input.action,
        input.requestId ?? null,
        input.friendshipId ?? null,
        input.metadata ? JSON.stringify(input.metadata) : null,
        input.now
      ]
    );
  }

}
