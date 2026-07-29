import { Injectable } from "@nestjs/common";
import { ConversationRepository } from "./conversation.repository.js";
import {
  ConversationDomainError,
  type MessageView
} from "./conversation.types.js";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

@Injectable()
export class ConversationService {
  constructor(private readonly repository: ConversationRepository) {}

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
      items: result.items,
      hasMore: result.hasMore,
      nextCursor: result.hasMore
        ? Buffer.from(String(offset + limit)).toString("base64url")
        : null,
      navigationUnread: result.navigationUnread
    };
  }

  getConversation(userId: string, conversationId: unknown): Promise<unknown> {
    return this.repository.getConversation(
      userId,
      this.uuid(conversationId, "CONVERSATION_ID_INVALID")
    );
  }

  async sendMessage(input: {
    userId: string;
    conversationId?: unknown;
    body: Record<string, unknown>;
    idempotencyKey?: string;
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
    return this.repository.sendTextMessage({
      userId: input.userId,
      conversationId,
      clientMessageId,
      text: input.body.text.trim(),
      replyToMessageId,
      now: new Date()
    });
  }

  listMessages(input: {
    userId: string;
    conversationId?: unknown;
    beforeSequence?: string;
    afterSequence?: string;
    anchorSequence?: string;
    limit?: string;
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
    return this.repository.listMessages({
      userId: input.userId,
      conversationId: this.uuid(
        input.conversationId,
        "CONVERSATION_ID_INVALID"
      ),
      beforeSequence: this.optionalSequence(input.beforeSequence, 1),
      afterSequence: this.optionalSequence(input.afterSequence, 0),
      anchorSequence: this.optionalSequence(input.anchorSequence, 1),
      limit: this.limit(input.limit, 50, 100)
    });
  }

  advanceReadCursor(input: {
    userId: string;
    conversationId?: unknown;
    lastReadSequence?: unknown;
    idempotencyKey?: string;
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
    return this.repository.advanceReadCursor({
      userId: input.userId,
      conversationId: this.uuid(
        input.conversationId,
        "CONVERSATION_ID_INVALID"
      ),
      lastReadSequence: input.lastReadSequence,
      now: new Date()
    });
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
