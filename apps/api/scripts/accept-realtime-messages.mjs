import { randomUUID } from "node:crypto";
import WebSocket from "ws";

const base = process.env.API_BASE_URL ?? "http://127.0.0.1:3000";
const wsUrl = new URL("/ws/v1", base.replace(/^http/, "ws")).toString();
const userA = "019f0000-0000-7000-8000-00000000000a";
const userB = "019f0000-0000-7000-8000-00000000000b";

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

async function api(
  path,
  { method = "GET", token, body, key, expected = [200] } = {}
) {
  const headers = {};
  if (token) headers.authorization = `Bearer ${token}`;
  if (key) headers["idempotency-key"] = key;
  if (body !== undefined) headers["content-type"] = "application/json";
  const response = await fetch(`${base}${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body)
  });
  const text = await response.text();
  const payload = text ? JSON.parse(text) : null;
  if (!expected.includes(response.status)) {
    throw new Error(
      `${method} ${path}: expected ${expected.join("/")}, got ${response.status} ${payload?.error?.code ?? ""}`
    );
  }
  return payload;
}

async function login(phoneNumber, deviceName) {
  const sent = await api("/auth/sms/send", {
    method: "POST",
    body: { countryCode: "+86", phoneNumber, purpose: "login" }
  });
  const verified = await api("/auth/sms/verify", {
    method: "POST",
    key: randomUUID(),
    body: {
      verificationId: sent.data.verificationId,
      code: process.env.STAGING_SMS_TEST_CODE,
      device: { platform: "ios", deviceName }
    }
  });
  return verified.data;
}

class Probe {
  constructor(socket) {
    this.socket = socket;
    this.events = [];
    this.waiters = new Set();
    socket.on("message", (raw) => {
      const event = JSON.parse(raw.toString());
      this.events.push(event);
      for (const waiter of this.waiters) waiter();
    });
  }

  send(event, payload, requestId = randomUUID()) {
    this.socket.send(JSON.stringify({ event, requestId, payload }));
    return requestId;
  }

  async waitFor(predicate, description, timeoutMs = 5_000) {
    const existing = this.events.find(predicate);
    if (existing) return existing;
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        this.waiters.delete(check);
        reject(new Error(`realtime timeout: ${description}`));
      }, timeoutMs);
      const check = () => {
        const match = this.events.find(predicate);
        if (!match) return;
        clearTimeout(timeout);
        this.waiters.delete(check);
        resolve(match);
      };
      this.waiters.add(check);
    });
  }

  count(predicate) {
    return this.events.filter(predicate).length;
  }

  close() {
    this.socket.close(1000, "acceptance complete");
  }
}

async function connect(token, resumeCursor = null) {
  const socket = new WebSocket(wsUrl, {
    headers: { authorization: `Bearer ${token}` }
  });
  await new Promise((resolve, reject) => {
    socket.once("open", resolve);
    socket.once("error", reject);
  });
  const probe = new Probe(socket);
  const requestId = probe.send("session.resume", { resumeCursor });
  const ready = await probe.waitFor(
    (event) =>
      event.event === "session.ready" && event.requestId === requestId,
    "session.ready"
  );
  return { probe, ready };
}

async function rejectUnauthenticatedSocket() {
  const socket = new WebSocket(wsUrl);
  const code = await new Promise((resolve, reject) => {
    const timeout = setTimeout(
      () => reject(new Error("unauthenticated socket stayed open")),
      5_000
    );
    socket.once("close", (closeCode) => {
      clearTimeout(timeout);
      resolve(closeCode);
    });
    socket.once("error", () => {});
  });
  assert(code === 4401, "unauthenticated realtime connection was not rejected");
}

assert(
  process.env.STAGING_TEST_PHONE_A &&
    process.env.STAGING_TEST_PHONE_B &&
    process.env.STAGING_SMS_TEST_CODE,
  "staging A/B realtime acceptance environment is incomplete"
);

const a = await login(
  process.env.STAGING_TEST_PHONE_A,
  "A realtime acceptance device"
);
const b = await login(
  process.env.STAGING_TEST_PHONE_B,
  "B realtime acceptance device"
);
assert(a.userId === userA && b.userId === userB, "A/B identity mismatch");

const friends = await api("/friends", { token: a.accessToken });
const friendB = friends.data.items.find((item) => item.userId === userB);
assert(friendB, "A/B accounts must be friends before realtime acceptance");
const conversationId = friendB.directConversationId;

const initialDetail = await api(`/conversations/${conversationId}`, {
  token: b.accessToken
});
await api(`/conversations/${conversationId}/read-cursor`, {
  method: "PUT",
  token: b.accessToken,
  key: randomUUID(),
  body: { lastReadSequence: initialDetail.data.latestSequence }
});

await rejectUnauthenticatedSocket();
const aSocket = await connect(a.accessToken);
const bSocketOne = await connect(b.accessToken);
const bSocketTwo = await connect(b.accessToken);

const firstClientMessageId = randomUUID();
const firstRequestId = aSocket.probe.send("message.send", {
  conversationId,
  clientMessageId: firstClientMessageId,
  type: "text",
  text: "A实时发送：B的两个连接都应收到"
});
const accepted = await aSocket.probe.waitFor(
  (event) =>
    event.event === "message.accepted" && event.requestId === firstRequestId,
  "message.accepted"
);
const firstCreated = (event) =>
  event.event === "message.created" &&
  event.payload.clientMessageId === firstClientMessageId;
await Promise.all([
  bSocketOne.probe.waitFor(firstCreated, "B connection one message.created"),
  bSocketTwo.probe.waitFor(firstCreated, "B connection two message.created")
]);
await bSocketOne.probe.waitFor(
  (event) =>
    event.event === "conversation.unread.changed" &&
    event.payload.conversationId === conversationId &&
    event.payload.unread.count >= 1,
  "receiver unread increment"
);

const beforeDuplicate = bSocketOne.probe.count(firstCreated);
const retryRequestId = aSocket.probe.send("message.send", {
  conversationId,
  clientMessageId: firstClientMessageId,
  type: "text",
  text: "A实时发送：B的两个连接都应收到"
});
const retryAccepted = await aSocket.probe.waitFor(
  (event) =>
    event.event === "message.accepted" && event.requestId === retryRequestId,
  "idempotent message.accepted"
);
assert(
  retryAccepted.payload.messageId === accepted.payload.messageId,
  "realtime idempotency returned another message"
);
await new Promise((resolve) => setTimeout(resolve, 300));
assert(
  bSocketOne.probe.count(firstCreated) === beforeDuplicate,
  "idempotent retry emitted another message.created"
);

const readRequestId = bSocketOne.probe.send("conversation.read", {
  conversationId,
  lastReadSequence: accepted.payload.sequence
});
await Promise.all([
  bSocketOne.probe.waitFor(
    (event) =>
      event.event === "conversation.unread.changed" &&
      event.payload.conversationId === conversationId &&
      event.payload.unread.count === 0 &&
      event.eventCursor !== bSocketOne.ready.payload.latestCursor,
    "first B connection unread clear"
  ),
  bSocketTwo.probe.waitFor(
    (event) =>
      event.event === "conversation.unread.changed" &&
      event.payload.conversationId === conversationId &&
      event.payload.unread.count === 0,
    "second B connection unread clear"
  )
]);
assert(readRequestId, "read request was not sent");

const resumeCursor =
  bSocketOne.probe.events.at(-1)?.eventCursor ??
  bSocketOne.ready.payload.latestCursor;
bSocketOne.probe.close();
await new Promise((resolve) => setTimeout(resolve, 100));

const offlineClientMessageId = randomUUID();
aSocket.probe.send("message.send", {
  conversationId,
  clientMessageId: offlineClientMessageId,
  type: "text",
  text: "A发送：断线连接恢复后应补到"
});
await bSocketTwo.probe.waitFor(
  (event) =>
    event.event === "message.created" &&
    event.payload.clientMessageId === offlineClientMessageId,
  "online B connection receives offline test message"
);
const resumedB = await connect(b.accessToken, resumeCursor);
assert(resumedB.ready.payload.resumed === true, "realtime session did not resume");
await resumedB.probe.waitFor(
  (event) =>
    event.event === "message.created" &&
    event.payload.clientMessageId === offlineClientMessageId,
  "replayed message after reconnect"
);
const synced = await api(
  `/api/v1/sync/events?afterCursor=${encodeURIComponent(resumeCursor)}&limit=100`,
  { token: b.accessToken }
);
assert(
  synced.data.events.some(
    (event) =>
      event.eventType === "message.created" &&
      event.payload.clientMessageId === offlineClientMessageId
  ),
  "REST event sync did not include the offline message"
);
assert(
  typeof synced.data.latestCursor === "string" &&
    synced.data.latestCursor !== "0-0",
  "REST event sync did not return a usable latest cursor"
);

await api(`/blocks/${userB}`, {
  method: "PUT",
  token: a.accessToken,
  key: randomUUID(),
  body: { reasonCode: "realtime_acceptance" }
});
const blockedClientMessageId = randomUUID();
const blockedRequestId = bSocketTwo.probe.send("message.send", {
  conversationId,
  clientMessageId: blockedClientMessageId,
  type: "text",
  text: "拉黑后实时消息不应发送"
});
const rejected = await bSocketTwo.probe.waitFor(
  (event) =>
    event.event === "message.rejected" &&
    event.requestId === blockedRequestId,
  "blocked message.rejected"
);
assert(
  rejected.payload.error.code === "DIRECT_MESSAGE_BLOCKED",
  "blocked realtime message returned the wrong error"
);
await api(`/blocks/${userB}`, {
  method: "DELETE",
  token: a.accessToken,
  key: randomUUID()
});

for (const connection of [
  aSocket.probe,
  bSocketTwo.probe,
  resumedB.probe
]) {
  connection.close();
}

console.log("ab_realtime_message_acceptance=passed");
