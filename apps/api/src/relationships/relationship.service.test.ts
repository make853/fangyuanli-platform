import assert from "node:assert/strict";
import test from "node:test";
import type { RelationshipRepository } from "./relationship.repository.js";
import type { ProfileIdentityService } from "../profiles/profile-identity.service.js";
import { RelationshipService } from "./relationship.service.js";
import { RelationshipDomainError } from "./relationship.types.js";
import { RequestHasher } from "./request-hasher.js";

const userA = "11111111-1111-4111-8111-111111111111";
const userB = "22222222-2222-4222-8222-222222222222";

function createService(repository: Record<string, unknown>): RelationshipService {
  process.env.REQUEST_HASH_KEY = "request-hash-key-for-tests-only-123456";
  return new RelationshipService(
    repository as unknown as RelationshipRepository,
    new RequestHasher()
  );
}

test("creates a trimmed friend request with a hashed idempotency key", async () => {
  let captured: Record<string, unknown> | undefined;
  const service = createService({
    async createRequest(input: Record<string, unknown>) {
      captured = input;
      return { requestId: "request" };
    }
  });

  await service.createRequest({
    senderUserId: userA,
    targetUserId: userB,
    applicationNote: "  羽毛球活动见过  ",
    idempotencyKey: "request-1"
  });

  assert.equal(captured?.applicationNote, "羽毛球活动见过");
  assert.equal(captured?.senderUserId, userA);
  assert.equal(captured?.targetUserId, userB);
  assert.equal(typeof captured?.idempotencyKeyHash, "string");
  assert.equal((captured?.idempotencyKeyHash as string).length, 64);
});

test("requires an application note and idempotency key", async () => {
  const service = createService({});
  await assert.rejects(
    service.createRequest({
      senderUserId: userA,
      targetUserId: userB,
      applicationNote: " ",
      idempotencyKey: "request-1"
    }),
    (error: unknown) =>
      error instanceof RelationshipDomainError &&
      error.code === "FRIEND_REQUEST_NOTE_REQUIRED"
  );
  await assert.rejects(
    service.createRequest({
      senderUserId: userA,
      targetUserId: userB,
      applicationNote: "你好"
    }),
    (error: unknown) =>
      error instanceof RelationshipDomainError &&
      error.code === "IDEMPOTENCY_KEY_REQUIRED"
  );
});

test("preserves explicit null remark and one-way post permission", async () => {
  let captured: Record<string, unknown> | undefined;
  const service = createService({
    async updateFriendSettings(input: Record<string, unknown>) {
      captured = input;
      return input;
    }
  });

  await service.updateFriendSettings({
    ownerUserId: userA,
    friendUserId: userB,
    body: {
      remarkName: null,
      canViewMyPosts: false,
      pinned: true
    },
    idempotencyKey: "settings-1"
  });

  assert.equal(captured?.remarkName, null);
  assert.equal(captured?.canViewMyPosts, false);
  assert.equal(captured?.pinned, true);
  assert.equal(captured?.ownerUserId, userA);
});

test("encodes the next page cursor without exposing an offset contract", async () => {
  const service = createService({
    async listFriends() {
      return { items: [{ userId: userB }], hasMore: true };
    }
  });
  const first = await service.listFriends({ userId: userA, limit: "1" });
  assert.equal(first.hasMore, true);
  assert.ok(first.nextCursor);

  let capturedOffset = -1;
  const nextService = createService({
    async listFriends(input: { offset: number }) {
      capturedOffset = input.offset;
      return { items: [], hasMore: false };
    }
  });
  await nextService.listFriends({
    userId: userA,
    limit: "1",
    cursor: first.nextCursor ?? undefined
  });
  assert.equal(capturedOffset, 1);
});

test("hydrates friend avatars without overwriting a local remark", async () => {
  process.env.REQUEST_HASH_KEY = "request-hash-key-for-tests-only-123456";
  const repository = {
    async listFriends() {
      return {
        items: [
          {
            userId: userB,
            displayName: "小远",
            nickname: "远山",
            remarkName: "小远",
            avatar: null,
            profileVersion: 1,
            canViewMyPosts: true,
            pinned: false,
            directConversationId: "33333333-3333-4333-8333-333333333333",
            updatedAt: "2026-08-02T00:00:00.000Z"
          }
        ],
        hasMore: false
      };
    }
  };
  const identities = {
    async getMany() {
      return new Map([
        [
          userB,
          {
            userId: userB,
            displayName: "远山",
            profileVersion: 4,
            avatar: {
              mediaId: "44444444-4444-4444-8444-444444444444",
              mediaType: "image",
              status: "ready",
              url: "https://media.example/avatar.webp",
              thumbnailUrl: "https://media.example/avatar-thumb.webp",
              coverUrl: null,
              width: 128,
              height: 128,
              durationMs: null,
              expiresAt: "2026-08-02T00:10:00.000Z"
            }
          }
        ]
      ]);
    }
  };
  const service = new RelationshipService(
    repository as unknown as RelationshipRepository,
    new RequestHasher(),
    identities as unknown as ProfileIdentityService
  );

  const result = await service.listFriends({ userId: userA });

  assert.equal(result.items[0].displayName, "小远");
  assert.equal(result.items[0].profileVersion, 4);
  assert.equal(result.items[0].avatar?.mediaId, "44444444-4444-4444-8444-444444444444");
});
