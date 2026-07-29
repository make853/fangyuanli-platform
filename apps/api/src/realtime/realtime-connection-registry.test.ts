import assert from "node:assert/strict";
import test from "node:test";
import { WebSocket } from "ws";
import { RealtimeConnectionRegistry } from "./realtime-connection-registry.js";
import { serverEvent } from "./realtime-protocol.js";
import type { RealtimeConnection } from "./realtime.types.js";

function connection(sent: string[]): RealtimeConnection {
  const socket = {
    readyState: WebSocket.OPEN,
    send(value: string) {
      sent.push(value);
    },
    close() {}
  } as unknown as WebSocket;
  return {
    socket,
    userId: "019f0000-0000-7000-8000-00000000000a",
    sessionId: "019f0000-0000-7000-8000-00000000000b",
    deviceId: "019f0000-0000-7000-8000-00000000000c",
    tokenVersion: 1,
    ready: false,
    lastPongAt: Date.now(),
    pending: []
  };
}

test("buffers events during resume and flushes only newer cursors in order", () => {
  const sent: string[] = [];
  const registry = new RealtimeConnectionRegistry();
  const target = connection(sent);
  registry.attach(target);

  registry.sendUser(
    target.userId,
    serverEvent({ event: "message.created", eventCursor: "12-0", payload: {} })
  );
  registry.sendUser(
    target.userId,
    serverEvent({ event: "message.created", eventCursor: "11-0", payload: {} })
  );
  registry.sendUser(
    target.userId,
    serverEvent({ event: "message.created", eventCursor: "10-0", payload: {} })
  );

  assert.equal(sent.length, 0);
  registry.flush(target, "10-0");
  assert.equal(target.ready, true);
  assert.deepEqual(
    sent.map((value) => JSON.parse(value).eventCursor),
    ["11-0", "12-0"]
  );
});
