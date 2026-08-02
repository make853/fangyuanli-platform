import { Injectable, Logger, Optional } from "@nestjs/common";
import { ProfileIdentityService } from "../profiles/profile-identity.service.js";
import type { UserIdentityView } from "../profiles/profile.types.js";
import { RealtimeTransport } from "../realtime/realtime-transport.js";
import { ConversationRepository } from "./conversation.repository.js";
import {
  ConversationDomainError,
  type ConversationSummary,
  type MessageView
} from "./conversation.types.js";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

@Injectable()
export class ConversationService {
  private readonly logger = new Logger(ConversationService.name);

  constructor(
    private readonly repository: ConversationRepository,
    @Optional() private readonly realtime?: RealtimeTransport,
    @Optional() private readonly identities?: ProfileIdentityService
  ) {}

  async listConversations(input: {
    userId: string;
    cursor?: string;
    limit?: string;
  }): Promise<unknown> {
    const { offset, limit } = this.page(input.cursor, input.limit, 20);
    const result = await this.repository.listConversations({
      userId: input.userId,
      offset,
      limit
    });
    return {
      items: await this.hydrateConversations(result.items),
      hasMore: result.hasMore,
      nextCursor: result.hasMore
        ? Buffer.from(String(offset + limit)).toString("base64url")
        : null,
      navigationUnread: result.navigationUnread
    };
  }

  async getConversation(userId: string, conversationId: unknown): Promise<unknown> {
    const conversation = await this.repository.getConversation(
      userId,
      this.uuid(conversationId, "CONVERSATION_ID_INVALID")
    );
    return this.hydrateConversation(conversation);
  }

  async syncConversationSnapshots(userId: string): Promise<{
    items: unknown[];
    hasMore: boolean;
  }> {
    const result = await this.repository.listConversations({
      userId,
      offset: 0,
      limit: 200
    });
    return {
      items: await this.hydrateConversations(result.items),
      hasMore: result.hasMore
    };
  }

  async sendMessage(input: {
    userId: string;
    conversationId?: unknown;
    body: Record<string, unknown>;
    idempotencyKey?: string;
    locationContextToken?: string;
  }): Promise<MessageView> {
    const conversationId = this.uuid(
      input.conversationId,
      "CONVERSATION_ID_INVALID"
    );
    this.idempotencyKey(input.idempotencyKey);
    const clientMessageId = this.uuid(
      input.body.clientMessageId,
      "CLIENT_MESSAGE_ID_INVALID"
    );
    if (input.body.type !== "text") {
      throw new ConversationDomainError(
        "MESSAGE_TYPE_NOT_READY",
        "当前阶段仅开放文字消息",
        422
      );
    }
    if (
      typeof input.body.text !== "string" ||
      !input.body.text.trim() ||
      input.body.text.length > 5000
    ) {
      throw new ConversationDomainError(
        "MESSAGE_TEXT_INVALID",
        "文字消息应为1至5000字",
        422
      );
    }
    const replyToMessageId =
      input.body.replyToMessageId === undefined ||
      input.body.replyToMessageId === null
        ? null
        : this.uuid(input.body.replyToMessageId, "REPLY_MESSAGE_ID_INVALID");
    const persisted = await this.repository.sendTextMessage({
      userId: input.userId,
      conversationId,
      clientMessageId,
      text: input.body.text.trim(),
      replyToMessageId,
      locationContextToken:
        input.locationContextToken ??
        (typeof input.body.locationContextToken === "string"
          ? input.body.locationContextToken
          : undefined),
      now: new Date()
    });
    const message = await this.hydrateMessage(persisted.message);
    if (persisted.created) {
      await this.publishMessageCreated(
        input.userId,
        message,
        input.locationContextToken ??
          (typeof input.body.locationContextToken === "string"
            ? input.body.locationContextToken
            : undefined)
      );
    }
    return message;
  }

  async listMessages(input: {
    userId: string;
    conversationId?: unknown;
    beforeSequence?: string;
    afterSequence?: string;
    anchorSequence?: string;
    limit?: string;
    locationContextToken?: string;
  }): Promise<unknown> {
    const selectors = [
      input.beforeSequence,
      input.afterSequence,
      input.anchorSequence
    ].filter((value) => value !== undefined);
    if (selectors.length > 1) {
      throw new ConversationDomainError(
        "MESSAGE_PAGE_MODE_INVALID",
        "消息分页参数不能同时使用",
        400
      );
    }
    const page = await this.repository.listMessages({
      userId: input.userId,
      conversationId: this.uuid(
        input.conversationId,
        "CONVERSATION_ID_INVALID"
      ),
      beforeSequence: this.optionalSequence(input.beforeSequence, 1),
      afterSequence: this.optionalSequence(input.afterSequence, 0),
      anchorSequence: this.optionalSequence(input.anchorSequence, 1),
      limit: this.limit(input.limit, 50, 100),
      locationContextToken: input.locationContextToken
    });
    return {
      ...page,
      items: await this.hydrateMessages(page.items)
    };
  }

  private async identityMap(
    userIds: string[]
  ): Promise<Map<string, UserIdentityView>> {
    return this.identities?.getMany(userIds) ?? new Map<string, UserIdentityView>();
  }

  private async hydrateConversation<T extends ConversationSummary>(
    conversation: T
  ): Promise<T> {
    return (await this.hydrateConversations([conversation]))[0] as T;
  }

  private async hydrateConversations<T extends ConversationSummary>(
    conversations: T[]
  ): Promise<T[]> {
    const identities = await this.identityMap(
      conversations.map((conversation) => conversation.peerUserId)
    );
    return conversations.map((conversation) => {
      const identity = identities.get(conversation.peerUserId);
      if (!identity) return conversation;
      return {
        ...conversation,
        avatar: identity.avatar,
        profileVersion: identity.profileVersion
      };
    });
  }

  private async hydrateMessage(message: MessageView): Promise<MessageView> {
    return (await this.hydrateMessages([message]))[0];
  }

  private async hydrateMessages(messages: MessageView[]): Promise<MessageView[]> {
    const identities = await this.identityMap(
      messages.flatMap((message) =>
        message.sender ? [message.sender.userId] : []
      )
    );
    return messages.map((message) => {
      const sender = message.sender;
      if (!sender) return message;
      const identity = identities.get(sender.userId);
      if (!identity) return message;
      return {
        ...message,
        sender: {
          ...sender,
          displayName: identity.displayName,
          avatar: identity.avatar,
          profileVersion: identity.profileVersion
        }
      };
    });
  }

  async advanceReadCursor(input: {
    userId: string;
    conversationId?: unknown;
    lastReadSequence?: unknown;
    idempotencyKey?: string;
    locationContextToken?: string;
  }): Promise<unknown> {
    this.idempotencyKey(input.idempotencyKey);
    if (
      typeof input.lastReadSequence !== "number" ||
      !Number.isSafeInteger(input.lastReadSequence) ||
      input.lastReadSequence < 0
    ) {
      throw new ConversationDomainError(
        "READ_SEQUENCE_INVALID",
        "已读序号无效",
        400
      );
    }
    const result = await this.repository.advanceReadCursor({
      userId: input.userId,
      conversationId: this.uuid(
        input.conversationId,
        "CONVERSATION_ID_INVALID"
      ),
      lastReadSequence: input.lastReadSequence,
      locationContextToken: input.locationContextToken,
      now: new Date()
    });
    await this.publishUnreadChanged(input.userId, result.conversationId);
    return result;
  }

  private async publishMessageCreated(
    actorUserId: string,
    message: MessageView,
    locationContextToken?: string
  ): Promise<void> {
    if (!this.realtime) return;
    try {
      const userIds = await this.repository.participantUserIds(
        actorUserId,
        message.conversationId,
        locationContextToken
      );
      await Promise.all(
        userIds.flatMap((userId) => [
          this.realtime!.publish(userId, "message.created", { ...message }),
          this.publishUnreadChanged(userId, message.conversationId)
        ])
      );
    } catch (error) {
      this.logger.error(
        `Message persisted but realtime publish failed: ${
          error instanceof Error ? error.message : String(error)
        }`
      );
    }
  }

  private async publishUnreadChanged(
    userId: string,
    conversationId: string
  ): Promise<void> {
    if (!this.realtime) return;
    try {
      const state = await this.repository.realtimeConversationState(
        userId,
        conversationId
      );
      await this.realtime.publish(userId, "conversation.unread.changed", {
        conversationId,
        unread: state.unread,
        navigationKey: state.navigationKey,
        navigationUnreadCount: state.navigationUnreadCount
      });
    } catch (error) {
      this.logger.error(
        `Unread state persisted but realtime publish failed: ${
          error instanceof Error ? error.message : String(error)
        }`
      );
    }
  }

  private uuid(value: unknown, code: string): string {
    if (typeof value !== "string" || !UUID_PATTERN.test(value)) {
      throw new ConversationDomainError(code, "标识格式无效", 400);
    }
    return value;
  }

  private idempotencyKey(value?: string): string {
    if (!value?.trim() || value.length > 200) {
      throw new ConversationDomainError(
        "IDEMPOTENCY_KEY_REQUIRED",
        "请求缺少有效的幂等键",
        400
      );
    }
    return value;
  }

  private optionalSequence(value: string | undefined, minimum: number): number | undefined {
    if (value === undefined) return undefined;
    const parsed = Number(value);
    if (!Number.isSafeInteger(parsed) || parsed < minimum) {
      throw new ConversationDomainError(
        "MESSAGE_SEQUENCE_INVALID",
        "消息序号无效",
        400
      );
    }
    return parsed;
  }

  private page(
    cursor: string | undefined,
    rawLimit: string | undefined,
    fallback: number
  ): { offset: number; limit: number } {
    const limit = this.limit(rawLimit, fallback, 50);
    if (!cursor) return { offset: 0, limit };
    try {
      const offset = Number(Buffer.from(cursor, "base64url").toString("utf8"));
      if (!Number.isSafeInteger(offset) || offset < 0) throw new Error();
      return { offset, limit };
    } catch {
      throw new ConversationDomainError("CURSOR_INVALID", "分页游标无效", 400);
    }
  }

  private limit(raw: string | undefined, fallback: number, maximum: number): number {
    const limit = raw === undefined ? fallback : Number(raw);
    if (!Number.isSafeInteger(limit) || limit < 1 || limit > maximum) {
      throw new ConversationDomainError("PAGINATION_INVALID", "分页参数无效", 400);
    }
    return limit;
  }
}
