import assert from "node:assert/strict";
import test from "node:test";
import { HttpException } from "@nestjs/common";
import { serverEvent } from "./realtime-protocol.js";
import { SyncController } from "./sync.controller.js";

const userId = "019f0000-0000-7000-8000-00000000000a";

test("maps retained realtime envelopes to the REST sync contract", async () => {
  const event = serverEvent({
    event: "message.created",
    eventCursor: "100-0",
    payload: { messageId: "019f0000-0000-7000-8000-00000000000b" }
  });
  const realtime = {
    async sync() {
      return {
        events: [event],
        latestCursor: "100-0",
        hasMore: false,
        expired: false
      };
    }
  };
  const controller = new SyncController(realtime as never, {} as never);
  const response = (await controller.events(
    userId,
    "0-0",
    "100",
    "request"
  )) as {
    data: { events: Array<Record<string, unknown>>; latestCursor: string };
  };

  assert.equal(response.data.latestCursor, "100-0");
  assert.equal(response.data.events[0].eventType, "message.created");
  assert.equal(response.data.events[0].eventCursor, "100-0");
});

test("returns current conversation snapshots when the retained cursor expired", async () => {
  const realtime = {
    async sync() {
      return {
        events: [],
        latestCursor: "200-0",
        hasMore: false,
        expired: true
      };
    }
  };
  const conversations = {
    async syncConversationSnapshots() {
      return {
        items: [{ conversationId: "019f0000-0000-7000-8000-00000000000c" }],
        hasMore: false
      };
    }
  };
  const controller = new SyncController(
    realtime as never,
    conversations as never
  );
  const response = (await controller.events(userId, "10-0")) as {
    data: { events: Array<Record<string, unknown>> };
  };

  assert.equal(response.data.events[0].eventType, "conversation.snapshot");
});

test("rejects an invalid REST sync limit", async () => {
  const controller = new SyncController({} as never, {} as never);
  await assert.rejects(
    controller.events(userId, "0-0", "500"),
    (error: unknown) =>
      error instanceof HttpException &&
      error.getStatus() === 400 &&
      (error.getResponse() as { error: { code: string } }).error.code ===
        "SYNC_LIMIT_INVALID"
  );
});
