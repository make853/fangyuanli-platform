import assert from "node:assert/strict";
import test from "node:test";
import { ConversationService } from "./conversation.service.js";
import {
  ConversationDomainError,
  type MessageView
} from "./conversation.types.js";

const userId = "019f0000-0000-7000-8000-00000000000a";
const conversationId = "019f0000-0000-7000-8000-00000000000c";
const clientMessageId = "019f0000-0000-7000-8000-00000000000d";

function message(text: string): MessageView {
  return {
    messageId: "019f0000-0000-7000-8000-00000000000e",
    clientMessageId,
    conversationId,
    sequence: 1,
    sender: { userId, displayName: "测试用户A", avatar: null },
    type: "text",
    text,
    payload: null,
    media: [],
    replyToMessageId: null,
    mentions: [],
    deliveryState: "sent",
    createdAt: new Date().toISOString(),
    expiresAt: null
  };
}

test("validates and trims a text message before repository persistence", async () => {
  let persistedText: string | undefined;
  const repository = {
    async sendTextMessage(input: { text: string }) {
      persistedText = input.text;
      return { message: message(input.text), created: true };
    }
  };
  const service = new ConversationService(repository as never);
  const result = await service.sendMessage({
    userId,
    conversationId,
    idempotencyKey: "send-once",
    body: {
      clientMessageId,
      type: "text",
      text: "  你好，B  "
    }
  });
  assert.equal(persistedText, "你好，B");
  assert.equal(result.text, "你好，B");
});

test("keeps media message types closed until the media pipeline is ready", async () => {
  const service = new ConversationService({} as never);
  await assert.rejects(
    service.sendMessage({
      userId,
      conversationId,
      idempotencyKey: "media-not-ready",
      body: {
        clientMessageId,
        type: "image",
        mediaIds: ["019f0000-0000-7000-8000-00000000000f"]
      }
    }),
    (error: unknown) =>
      error instanceof ConversationDomainError &&
      error.code === "MESSAGE_TYPE_NOT_READY" &&
      error.status === 422
  );
});

test("requires one message paging mode at a time", () => {
  const service = new ConversationService({} as never);
  assert.throws(
    () => service.listMessages({
      userId,
      conversationId,
      beforeSequence: "10",
      afterSequence: "4"
    }),
    (error: unknown) =>
      error instanceof ConversationDomainError &&
      error.code === "MESSAGE_PAGE_MODE_INVALID"
  );
});

test("rejects a read cursor that is not a nonnegative safe integer", async () => {
  const service = new ConversationService({} as never);
  await assert.rejects(
    service.advanceReadCursor({
      userId,
      conversationId,
      idempotencyKey: "read-cursor",
      lastReadSequence: -1
    }),
    (error: unknown) =>
      error instanceof ConversationDomainError &&
      error.code === "READ_SEQUENCE_INVALID"
  );
});

test("requires an idempotency key for message writes", async () => {
  const service = new ConversationService({} as never);
  await assert.rejects(
    service.sendMessage({
      userId,
      conversationId,
      body: { clientMessageId, type: "text", text: "不会写入" }
    }),
    (error: unknown) =>
      error instanceof ConversationDomainError &&
      error.code === "IDEMPOTENCY_KEY_REQUIRED"
  );
});

test("publishes a new message and unread state to both participants", async () => {
  const published: Array<{ userId: string; event: string }> = [];
  const otherUserId = "019f0000-0000-7000-8000-00000000000f";
  const repository = {
    async sendTextMessage() {
      return { message: message("实时消息"), created: true };
    },
    async participantUserIds() {
      return [userId, otherUserId];
    },
    async realtimeConversationState(targetUserId: string) {
      return {
        conversationId,
        unread: {
          count: targetUserId === otherUserId ? 1 : 0,
          appearance: targetUserId === otherUserId ? "red" : "none",
          firstUnreadSequence: targetUserId === otherUserId ? 1 : null
        },
        navigationUnreadCount: targetUserId === otherUserId ? 1 : 0
      };
    }
  };
  const realtime = {
    async publish(targetUserId: string, event: string) {
      published.push({ userId: targetUserId, event });
      return {};
    }
  };
  const service = new ConversationService(repository as never, realtime as never);

  await service.sendMessage({
    userId,
    conversationId,
    idempotencyKey: "realtime-send",
    body: { clientMessageId, type: "text", text: "实时消息" }
  });

  assert.equal(published.length, 4);
  assert.deepEqual(
    published
      .map((item) => `${item.userId}:${item.event}`)
      .sort(),
    [
      `${otherUserId}:conversation.unread.changed`,
      `${otherUserId}:message.created`,
      `${userId}:conversation.unread.changed`,
      `${userId}:message.created`
    ].sort()
  );
});

test("does not republish an idempotent duplicate message", async () => {
  let publishCount = 0;
  const repository = {
    async sendTextMessage() {
      return { message: message("已经发送"), created: false };
    }
  };
  const realtime = {
    async publish() {
      publishCount += 1;
      return {};
    }
  };
  const service = new ConversationService(repository as never, realtime as never);

  await service.sendMessage({
    userId,
    conversationId,
    idempotencyKey: "duplicate-send",
    body: { clientMessageId, type: "text", text: "已经发送" }
  });

  assert.equal(publishCount, 0);
});

test("publishes the resulting unread state to all devices after mark-read", async () => {
  const events: string[] = [];
  const repository = {
    async advanceReadCursor() {
      return {
        conversationId,
        lastReadSequence: 4,
        unread: {
          count: 0,
          appearance: "none",
          firstUnreadSequence: null
        },
        navigationUnreadDelta: -2
      };
    },
    async realtimeConversationState() {
      return {
        conversationId,
        unread: {
          count: 0,
          appearance: "none",
          firstUnreadSequence: null
        },
        navigationUnreadCount: 0
      };
    }
  };
  const realtime = {
    async publish(_targetUserId: string, event: string) {
      events.push(event);
      return {};
    }
  };
  const service = new ConversationService(repository as never, realtime as never);

  await service.advanceReadCursor({
    userId,
    conversationId,
    lastReadSequence: 4,
    idempotencyKey: "read-realtime"
  });

  assert.deepEqual(events, ["conversation.unread.changed"]);
});
