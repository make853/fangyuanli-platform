import { Injectable } from "@nestjs/common";
import { RelationshipRepository } from "./relationship.repository.js";
import { RequestHasher } from "./request-hasher.js";
import {
  RelationshipDomainError,
  type BlockView,
  type FriendDecisionView,
  type FriendRequestView,
  type FriendView
} from "./relationship.types.js";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

type Page<T> = {
  items: T[];
  nextCursor: string | null;
  hasMore: boolean;
};

@Injectable()
export class RelationshipService {
  constructor(
    private readonly repository: RelationshipRepository,
    private readonly requestHasher: RequestHasher
  ) {}

  async createRequest(input: {
    senderUserId: string;
    targetUserId?: unknown;
    applicationNote?: unknown;
    idempotencyKey?: string;
  }): Promise<FriendRequestView> {
    const targetUserId = this.uuid(input.targetUserId, "USER_ID_INVALID");
    const note =
      typeof input.applicationNote === "string"
        ? input.applicationNote.trim()
        : "";
    if (!note || note.length > 200) {
      throw new RelationshipDomainError(
        "FRIEND_REQUEST_NOTE_REQUIRED",
        "请填写1至200字的申请说明",
        422
      );
    }
    const idempotencyKey = this.idempotencyKey(input.idempotencyKey);
    return this.repository.createRequest({
      senderUserId: input.senderUserId,
      targetUserId,
      applicationNote: note,
      idempotencyKeyHash: this.requestHasher.hash(idempotencyKey),
      now: new Date()
    });
  }

  async listRequests(input: {
    userId: string;
    direction?: string;
    status?: string;
    cursor?: string;
    limit?: string;
  }): Promise<Page<FriendRequestView>> {
    const directions = ["received", "sent", "all"] as const;
    const statuses = ["pending", "accepted", "rejected", "all"] as const;
    const direction = directions.includes(input.direction as (typeof directions)[number])
      ? (input.direction as (typeof directions)[number])
      : "received";
    const status = statuses.includes(input.status as (typeof statuses)[number])
      ? (input.status as (typeof statuses)[number])
      : "all";
    const { offset, limit } = this.page(input.cursor, input.limit);
    const result = await this.repository.listRequests({
      userId: input.userId,
      direction,
      status,
      offset,
      limit
    });
    return this.pageResult(result, offset, limit);
  }

  async decideRequest(input: {
    receiverUserId: string;
    requestId?: unknown;
    decision?: unknown;
    idempotencyKey?: string;
  }): Promise<FriendDecisionView> {
    const requestId = this.uuid(input.requestId, "FRIEND_REQUEST_ID_INVALID");
    if (input.decision !== "accept" && input.decision !== "reject") {
      throw new RelationshipDomainError(
        "FRIEND_REQUEST_DECISION_INVALID",
        "请选择同意或拒绝",
        400
      );
    }
    this.idempotencyKey(input.idempotencyKey);
    return this.repository.decideRequest({
      requestId,
      receiverUserId: input.receiverUserId,
      decision: input.decision,
      now: new Date()
    });
  }

  async listFriends(input: {
    userId: string;
    keyword?: string;
    cursor?: string;
    limit?: string;
  }): Promise<Page<FriendView>> {
    const keyword = input.keyword?.trim();
    if (keyword && keyword.length > 64) {
      throw new RelationshipDomainError("FRIEND_KEYWORD_INVALID", "搜索词过长", 400);
    }
    const { offset, limit } = this.page(input.cursor, input.limit);
    const result = await this.repository.listFriends({
      userId: input.userId,
      keyword: keyword || undefined,
      offset,
      limit
    });
    return this.pageResult(result, offset, limit);
  }

  async updateFriendSettings(input: {
    ownerUserId: string;
    friendUserId?: unknown;
    body: Record<string, unknown>;
    idempotencyKey?: string;
  }): Promise<unknown> {
    const friendUserId = this.uuid(input.friendUserId, "USER_ID_INVALID");
    this.idempotencyKey(input.idempotencyKey);
    const hasRemark = Object.hasOwn(input.body, "remarkName");
    const hasPosts = Object.hasOwn(input.body, "canViewMyPosts");
    const hasPinned = Object.hasOwn(input.body, "pinned");
    if (!hasRemark && !hasPosts && !hasPinned) {
      throw new RelationshipDomainError("FRIEND_SETTINGS_EMPTY", "没有需要修改的设置", 400);
    }
    const remarkName = input.body.remarkName;
    if (
      hasRemark &&
      remarkName !== null &&
      (typeof remarkName !== "string" || remarkName.trim().length > 64)
    ) {
      throw new RelationshipDomainError("FRIEND_REMARK_INVALID", "备注不能超过64字", 400);
    }
    if (hasPosts && typeof input.body.canViewMyPosts !== "boolean") {
      throw new RelationshipDomainError("FRIEND_PERMISSION_INVALID", "动态权限无效", 400);
    }
    if (hasPinned && typeof input.body.pinned !== "boolean") {
      throw new RelationshipDomainError("FRIEND_PIN_INVALID", "置顶设置无效", 400);
    }
    return this.repository.updateFriendSettings({
      ownerUserId: input.ownerUserId,
      friendUserId,
      remarkName: hasRemark
        ? remarkName === null
          ? null
          : (remarkName as string).trim() || null
        : undefined,
      canViewMyPosts: hasPosts
        ? (input.body.canViewMyPosts as boolean)
        : undefined,
      pinned: hasPinned ? (input.body.pinned as boolean) : undefined,
      now: new Date()
    });
  }

  async deleteFriend(input: {
    userId: string;
    friendUserId?: unknown;
    idempotencyKey?: string;
  }): Promise<void> {
    const friendUserId = this.uuid(input.friendUserId, "USER_ID_INVALID");
    this.idempotencyKey(input.idempotencyKey);
    await this.repository.deleteFriend(input.userId, friendUserId, new Date());
  }

  async block(input: {
    blockerUserId: string;
    targetUserId?: unknown;
    reasonCode?: unknown;
    idempotencyKey?: string;
  }): Promise<BlockView> {
    const targetUserId = this.uuid(input.targetUserId, "USER_ID_INVALID");
    this.idempotencyKey(input.idempotencyKey);
    if (
      input.reasonCode !== undefined &&
      (typeof input.reasonCode !== "string" || input.reasonCode.length > 32)
    ) {
      throw new RelationshipDomainError("BLOCK_REASON_INVALID", "拉黑原因无效", 400);
    }
    return this.repository.block({
      blockerUserId: input.blockerUserId,
      targetUserId,
      reasonCode: input.reasonCode as string | undefined,
      now: new Date()
    });
  }

  async unblock(input: {
    blockerUserId: string;
    targetUserId?: unknown;
    idempotencyKey?: string;
  }): Promise<BlockView> {
    const targetUserId = this.uuid(input.targetUserId, "USER_ID_INVALID");
    this.idempotencyKey(input.idempotencyKey);
    return this.repository.unblock({
      blockerUserId: input.blockerUserId,
      targetUserId,
      now: new Date()
    });
  }

  async listBlocks(input: {
    blockerUserId: string;
    cursor?: string;
    limit?: string;
  }): Promise<Page<BlockView>> {
    const { offset, limit } = this.page(input.cursor, input.limit);
    const result = await this.repository.listBlocks({
      blockerUserId: input.blockerUserId,
      offset,
      limit
    });
    return this.pageResult(result, offset, limit);
  }

  private uuid(value: unknown, code: string): string {
    if (typeof value !== "string" || !UUID_PATTERN.test(value)) {
      throw new RelationshipDomainError(code, "标识格式无效", 400);
    }
    return value;
  }

  private idempotencyKey(value?: string): string {
    if (!value?.trim() || value.length > 200) {
      throw new RelationshipDomainError(
        "IDEMPOTENCY_KEY_REQUIRED",
        "请求缺少有效的幂等键",
        400
      );
    }
    return value;
  }

  private page(cursor?: string, rawLimit?: string): { offset: number; limit: number } {
    const limit = rawLimit === undefined ? 20 : Number(rawLimit);
    if (!Number.isInteger(limit) || limit < 1 || limit > 50) {
      throw new RelationshipDomainError("PAGINATION_INVALID", "分页参数无效", 400);
    }
    if (!cursor) {
      return { offset: 0, limit };
    }
    try {
      const offset = Number(Buffer.from(cursor, "base64url").toString("utf8"));
      if (!Number.isInteger(offset) || offset < 0) {
        throw new Error("Invalid offset");
      }
      return { offset, limit };
    } catch {
      throw new RelationshipDomainError("CURSOR_INVALID", "分页游标无效", 400);
    }
  }

  private pageResult<T>(
    result: { items: T[]; hasMore: boolean },
    offset: number,
    limit: number
  ): Page<T> {
    return {
      items: result.items,
      hasMore: result.hasMore,
      nextCursor: result.hasMore
        ? Buffer.from(String(offset + limit)).toString("base64url")
        : null
    };
  }
}
