import { randomUUID } from "node:crypto";

const base = process.env.API_BASE_URL ?? "http://127.0.0.1:3000";
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
  return { status: response.status, payload };
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
      verificationId: sent.payload.data.verificationId,
      code: process.env.STAGING_SMS_TEST_CODE,
      device: { platform: "ios", deviceName }
    }
  });
  return verified.payload.data;
}

assert(
  process.env.STAGING_TEST_PHONE_A &&
    process.env.STAGING_TEST_PHONE_B &&
    process.env.STAGING_SMS_TEST_CODE,
  "staging A/B message acceptance environment is incomplete"
);

const a = await login(
  process.env.STAGING_TEST_PHONE_A,
  "A message acceptance device"
);
const b = await login(
  process.env.STAGING_TEST_PHONE_B,
  "B message acceptance device"
);
assert(a.userId === userA && b.userId === userB, "A/B identity mismatch");

const friends = await api("/friends", { token: a.accessToken });
const friendB = friends.payload.data.items.find((item) => item.userId === userB);
assert(friendB, "A/B accounts must be friends before message acceptance");
const conversationId = friendB.directConversationId;

const initialDetail = await api(`/conversations/${conversationId}`, {
  token: b.accessToken
});
await api(`/conversations/${conversationId}/read-cursor`, {
  method: "PUT",
  token: b.accessToken,
  key: randomUUID(),
  body: { lastReadSequence: initialDetail.payload.data.latestSequence }
});
await api(`/conversations/${conversationId}/messages`, {
  method: "POST",
  key: randomUUID(),
  body: { clientMessageId: randomUUID(), type: "text", text: "未登录不应发送" },
  expected: [401]
});

const duplicateClientId = randomUUID();
const duplicateKey = randomUUID();
const first = await api(`/conversations/${conversationId}/messages`, {
  method: "POST",
  token: a.accessToken,
  key: duplicateKey,
  body: {
    clientMessageId: duplicateClientId,
    type: "text",
    text: "A发送：断网重试只保留一条"
  },
  expected: [201]
});
const retried = await api(`/conversations/${conversationId}/messages`, {
  method: "POST",
  token: a.accessToken,
  key: duplicateKey,
  body: {
    clientMessageId: duplicateClientId,
    type: "text",
    text: "A发送：断网重试只保留一条"
  },
  expected: [201]
});
assert(
  first.payload.data.messageId === retried.payload.data.messageId &&
    first.payload.data.sequence === retried.payload.data.sequence,
  "message idempotency failed"
);

const [fromA, fromB] = await Promise.all([
  api(`/conversations/${conversationId}/messages`, {
    method: "POST",
    token: a.accessToken,
    key: randomUUID(),
    body: {
      clientMessageId: randomUUID(),
      type: "text",
      text: "A并发发送"
    },
    expected: [201]
  }),
  api(`/conversations/${conversationId}/messages`, {
    method: "POST",
    token: b.accessToken,
    key: randomUUID(),
    body: {
      clientMessageId: randomUUID(),
      type: "text",
      text: "B并发发送"
    },
    expected: [201]
  })
]);
const concurrentSequences = [
  fromA.payload.data.sequence,
  fromB.payload.data.sequence
].sort((left, right) => left - right);
assert(
  concurrentSequences[1] === concurrentSequences[0] + 1,
  "concurrent messages are not sequential"
);

const increment = await api(
  `/conversations/${conversationId}/messages?afterSequence=${initialDetail.payload.data.latestSequence}&limit=10`,
  { token: b.accessToken }
);
assert(increment.payload.data.items.length === 3, "incremental history is incomplete");
assert(
  increment.payload.data.items.every(
    (item, index, items) => index === 0 || item.sequence > items[index - 1].sequence
  ),
  "history is not ordered by server sequence"
);
const anchor = await api(
  `/conversations/${conversationId}/messages?anchorSequence=${first.payload.data.sequence}&limit=3`,
  { token: b.accessToken }
);
assert(
  anchor.payload.data.items.some(
    (item) => item.messageId === first.payload.data.messageId
  ),
  "anchor history does not include the target message"
);

const bConversations = await api("/conversations", { token: b.accessToken });
const bSummary = bConversations.payload.data.items.find(
  (item) => item.conversationId === conversationId
);
assert(
  bSummary?.unread.count === 2 &&
    bSummary.unread.firstUnreadSequence === first.payload.data.sequence,
  "receiver unread state is incorrect"
);
assert(
  bConversations.payload.data.navigationUnread >= 2,
  "friend navigation unread count is incorrect"
);

const latestSequence = Math.max(
  first.payload.data.sequence,
  fromA.payload.data.sequence,
  fromB.payload.data.sequence
);
const read = await api(`/conversations/${conversationId}/read-cursor`, {
  method: "PUT",
  token: b.accessToken,
  key: randomUUID(),
  body: { lastReadSequence: latestSequence }
});
assert(
  read.payload.data.unread.count === 0 &&
    read.payload.data.unread.firstUnreadSequence === null,
  "read cursor did not clear unread state"
);
const staleRead = await api(`/conversations/${conversationId}/read-cursor`, {
  method: "PUT",
  token: b.accessToken,
  key: randomUUID(),
  body: { lastReadSequence: 0 }
});
assert(
  staleRead.payload.data.lastReadSequence === latestSequence,
  "read cursor moved backwards"
);

await api(`/blocks/${userB}`, {
  method: "PUT",
  token: a.accessToken,
  key: randomUUID(),
  body: { reasonCode: "message_acceptance" }
});
await api(`/conversations/${conversationId}/messages`, {
  method: "POST",
  token: b.accessToken,
  key: randomUUID(),
  body: {
    clientMessageId: randomUUID(),
    type: "text",
    text: "拉黑后不应发送"
  },
  expected: [403]
});
const retryAfterBlock = await api(
  `/conversations/${conversationId}/messages`,
  {
    method: "POST",
    token: a.accessToken,
    key: duplicateKey,
    body: {
      clientMessageId: duplicateClientId,
      type: "text",
      text: "A发送：断网重试只保留一条"
    },
    expected: [201]
  }
);
assert(
  retryAfterBlock.payload.data.messageId === first.payload.data.messageId,
  "persisted retry was not acknowledged after relationship changed"
);
await api(`/blocks/${userB}`, {
  method: "DELETE",
  token: a.accessToken,
  key: randomUUID()
});

console.log("ab_direct_message_acceptance=passed");
