import assert from "node:assert/strict";
import test from "node:test";
import {
  compareRedisCursors,
  normalizeResumeCursor,
  parseClientEvent,
  RealtimeProtocolError,
  serverEvent
} from "./realtime-protocol.js";

const requestId = "019f0000-0000-7000-8000-000000000001";

test("parses a contract-shaped realtime client event", () => {
  const parsed = parseClientEvent(
    JSON.stringify({
      event: "session.resume",
      requestId,
      payload: { resumeCursor: "123-4" }
    })
  );
  assert.equal(parsed.event, "session.resume");
  assert.equal(parsed.requestId, requestId);
  assert.deepEqual(parsed.payload, { resumeCursor: "123-4" });
});

test("rejects malformed JSON and invalid request identifiers", () => {
  assert.throws(
    () => parseClientEvent("{"),
    (error: unknown) =>
      error instanceof RealtimeProtocolError &&
      error.code === "REALTIME_JSON_INVALID"
  );
  assert.throws(
    () =>
      parseClientEvent(
        JSON.stringify({ event: "session.resume", requestId: "bad", payload: {} })
      ),
    (error: unknown) =>
      error instanceof RealtimeProtocolError &&
      error.code === "REALTIME_EVENT_INVALID"
  );
});

test("normalizes and orders Redis stream cursors without number precision loss", () => {
  assert.equal(normalizeResumeCursor(null), null);
  assert.equal(normalizeResumeCursor("999999999999999999-2"), "999999999999999999-2");
  assert.equal(compareRedisCursors("100-9", "101-0"), -1);
  assert.equal(compareRedisCursors("101-2", "101-1"), 1);
  assert.equal(compareRedisCursors("101-2", "101-2"), 0);
  assert.throws(
    () => normalizeResumeCursor("not-a-cursor"),
    (error: unknown) =>
      error instanceof RealtimeProtocolError &&
      error.code === "REALTIME_CURSOR_INVALID"
  );
});

test("creates a complete server event envelope", () => {
  const event = serverEvent({
    event: "session.ready",
    eventCursor: "10-0",
    requestId,
    payload: { resumed: false }
  });
  assert.equal(event.event, "session.ready");
  assert.equal(event.eventCursor, "10-0");
  assert.equal(event.requestId, requestId);
  assert.equal(typeof event.eventId, "string");
  assert.equal(typeof event.serverTime, "string");
});
