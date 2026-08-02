import { Injectable, Optional } from "@nestjs/common";
import { ProfileIdentityService } from "../profiles/profile-identity.service.js";
import type { UserIdentityView } from "../profiles/profile.types.js";
import { RelationshipRepository } from "./relationship.repository.js";
import { RequestHasher } from "./request-hasher.js";
import {
  RelationshipDomainError,
  type BlockView,
  type FriendDecisionView,
  type FriendRequestView,
  type FriendView,
  type UserSummary
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
    private readonly requestHasher: RequestHasher,
    @Optional() private readonly identities?: ProfileIdentityService
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
    const request = await this.repository.createRequest({
      senderUserId: input.senderUserId,
      targetUserId,
      applicationNote: note,
      idempotencyKeyHash: this.requestHasher.hash(idempotencyKey),
      now: new Date()
    });
    return this.hydrateRequest(request);
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
    const page = this.pageResult(result, offset, limit);
    return {
      ...page,
      items: await this.hydrateRequests(page.items)
    };
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
    const decision = await this.repository.decideRequest({
      requestId,
      receiverUserId: input.receiverUserId,
      decision: input.decision,
      now: new Date()
    });
    return {
      ...decision,
      request: await this.hydrateRequest(decision.request)
    };
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
    const page = this.pageResult(result, offset, limit);
    return {
      ...page,
      items: await this.hydrateFriends(page.items)
    };
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
    const result = await this.repository.block({
      blockerUserId: input.blockerUserId,
      targetUserId,
      reasonCode: input.reasonCode as string | undefined,
      now: new Date()
    });
    return this.hydrateBlock(result);
  }

  async unblock(input: {
    blockerUserId: string;
    targetUserId?: unknown;
    idempotencyKey?: string;
  }): Promise<BlockView> {
    const targetUserId = this.uuid(input.targetUserId, "USER_ID_INVALID");
    this.idempotencyKey(input.idempotencyKey);
    const result = await this.repository.unblock({
      blockerUserId: input.blockerUserId,
      targetUserId,
      now: new Date()
    });
    return this.hydrateBlock(result);
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
    const page = this.pageResult(result, offset, limit);
    return {
      ...page,
      items: await this.hydrateBlocks(page.items)
    };
  }

  private async identityMap(
    userIds: string[]
  ): Promise<Map<string, UserIdentityView>> {
    return this.identities?.getMany(userIds) ?? new Map<string, UserIdentityView>();
  }

  private applyIdentity<T extends UserSummary>(
    summary: T,
    identity: UserIdentityView | undefined,
    preserveDisplayName = false
  ): T {
    if (!identity) return summary;
    return {
      ...summary,
      displayName: preserveDisplayName
        ? summary.displayName
        : identity.displayName,
      avatar: identity.avatar,
      profileVersion: identity.profileVersion
    };
  }

  private async hydrateRequest(
    request: FriendRequestView
  ): Promise<FriendRequestView> {
    return (await this.hydrateRequests([request]))[0];
  }

  private async hydrateRequests(
    requests: FriendRequestView[]
  ): Promise<FriendRequestView[]> {
    if (!this.identities) return requests;
    const identities = await this.identityMap(
      requests.flatMap((request) => [
        request.sender.userId,
        request.receiver.userId
      ])
    );
    return requests.map((request) => ({
      ...request,
      sender: this.applyIdentity(
        request.sender,
        identities.get(request.sender.userId)
      ),
      receiver: this.applyIdentity(
        request.receiver,
        identities.get(request.receiver.userId)
      )
    }));
  }

  private async hydrateFriends(friends: FriendView[]): Promise<FriendView[]> {
    if (!this.identities) return friends;
    const identities = await this.identityMap(
      friends.map((friend) => friend.userId)
    );
    return friends.map((friend) =>
      this.applyIdentity(friend, identities.get(friend.userId), true)
    );
  }

  private async hydrateBlock(block: BlockView): Promise<BlockView> {
    return (await this.hydrateBlocks([block]))[0];
  }

  private async hydrateBlocks(blocks: BlockView[]): Promise<BlockView[]> {
    if (!this.identities) return blocks;
    const identities = await this.identityMap(
      blocks.map((block) => block.target.userId)
    );
    return blocks.map((block) => ({
      ...block,
      target: this.applyIdentity(
        block.target,
        identities.get(block.target.userId)
      )
    }));
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
