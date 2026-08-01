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
  return payload?.data;
}

async function login(phoneNumber, deviceName) {
  const sent = await api("/auth/sms/send", {
    method: "POST",
    body: { countryCode: "+86", phoneNumber, purpose: "login" }
  });
  return api("/auth/sms/verify", {
    method: "POST",
    key: randomUUID(),
    body: {
      verificationId: sent.verificationId,
      code: process.env.STAGING_SMS_TEST_CODE,
      device: { platform: "ios", deviceName }
    }
  });
}

assert(
  process.env.STAGING_TEST_PHONE_A &&
    process.env.STAGING_TEST_PHONE_B &&
    process.env.STAGING_SMS_TEST_CODE,
  "staging A/B profile acceptance environment is incomplete"
);

const a = await login(process.env.STAGING_TEST_PHONE_A, "A profile acceptance");
const b = await login(process.env.STAGING_TEST_PHONE_B, "B profile acceptance");
assert(a.userId === userA && b.userId === userB, "A/B identity mismatch");

const originalProfile = await api("/me", { token: a.accessToken });
const originalPrivacy = await api("/me/privacy", { token: a.accessToken });
let blocked = false;

try {
  const updated = await api("/me", {
    method: "PATCH",
    token: a.accessToken,
    key: randomUUID(),
    body: {
      expectedVersion: originalProfile.profileVersion,
      nickname: "A资料验收",
      gender: "female",
      signature: "资料权限验收签名"
    }
  });
  assert(updated.nickname === "A资料验收", "self profile update was not saved");
  assert(
    updated.profileVersion === originalProfile.profileVersion + 1,
    "profile version did not advance"
  );

  const friendView = await api(`/users/${userA}`, { token: b.accessToken });
  assert(friendView.profileVisibility === "full", "friend profile was limited");
  assert(friendView.nickname === "A资料验收", "friend did not see new nickname");

  await api("/me/privacy", {
    method: "PATCH",
    token: a.accessToken,
    key: randomUUID(),
    body: { strangersCanViewProfile: false }
  });
  const friendAfterPrivacy = await api(`/users/${userA}`, {
    token: b.accessToken
  });
  assert(
    friendAfterPrivacy.profileVisibility === "full",
    "friend visibility should override stranger privacy"
  );

  await api(`/blocks/${userB}`, {
    method: "PUT",
    token: a.accessToken,
    key: randomUUID(),
    body: {}
  });
  blocked = true;
  const blockedView = await api(`/users/${userA}`, { token: b.accessToken });
  assert(blockedView.profileVisibility === "limited", "blocked view was not limited");
  assert(blockedView.nickname === null, "limited view leaked nickname");
  assert(
    blockedView.fangyuanNumber === null,
    "limited view leaked Fangyuan number"
  );
  assert(
    blockedView.signature === "资料权限验收签名",
    "limited view should preserve the signature"
  );
} finally {
  if (blocked) {
    await api(`/blocks/${userB}`, {
      method: "DELETE",
      token: a.accessToken,
      key: randomUUID()
    });
  }
  const latest = await api("/me", { token: a.accessToken });
  await api("/me", {
    method: "PATCH",
    token: a.accessToken,
    key: randomUUID(),
    body: {
      expectedVersion: latest.profileVersion,
      nickname: originalProfile.nickname,
      gender:
        originalProfile.gender === "hidden"
          ? "unspecified"
          : originalProfile.gender,
      signature: originalProfile.signature
    }
  });
  await api("/me/privacy", {
    method: "PATCH",
    token: a.accessToken,
    key: randomUUID(),
    body: {
      strangersCanViewProfile: originalPrivacy.strangersCanViewProfile,
      searchableByFangyuanNumber: originalPrivacy.searchableByFangyuanNumber,
      globalGroupMuted: originalPrivacy.globalGroupMuted
    }
  });
}

console.log("ab_profile_acceptance=passed");
