import assert from "node:assert/strict";
import test from "node:test";
import type { MediaDeliveryService } from "../media/media-delivery.service.js";
import type {
  MediaDeliveryReference,
  MediaView
} from "../media/media.types.js";
import type { ProfileRepository } from "./profile.repository.js";
import type { RealtimeTransport } from "../realtime/realtime-transport.js";
import { ProfileService } from "./profile.service.js";
import {
  ProfileDomainError,
  type PrivacyPatch,
  type PrivacySettingsView,
  type ProfilePatch,
  type ProfileProjection,
  type ProfileView
} from "./profile.types.js";

const userId = "019f0000-0000-7000-8000-00000000000a";
const targetUserId = "019f0000-0000-7000-8000-00000000000b";

function profile(overrides: Partial<ProfileView> = {}): ProfileView {
  return {
    userId,
    displayName: "小桃子",
    avatar: null,
    fangyuanNumber: "FY000000000001",
    nickname: "小桃子",
    gender: "unspecified",
    signature: "",
    background: null,
    profileVisibility: "full",
    profileVersion: 1,
    relationship: {
      state: "self",
      canStartDirectChat: false,
      isBlockedByMe: false,
      hasBlockedMe: false,
      canViewMyPosts: false
    },
    allowedActions: ["editProfile", "editPrivacy"],
    ...overrides
  };
}

function projection(
  overrides: Partial<ProfileProjection> = {}
): ProfileProjection {
  const { avatar: _avatar, background: _background, ...base } = profile();
  return {
    ...base,
    avatarReference: null,
    backgroundReference: null,
    ...overrides
  };
}

function mediaReference(mediaId: string): MediaDeliveryReference {
  return {
    mediaId,
    mediaType: "image",
    status: "ready",
    displayObjectKey: `processed/${mediaId}/display.webp`,
    thumbnailObjectKey: `processed/${mediaId}/thumbnail.webp`,
    coverObjectKey: null,
    width: 512,
    height: 512,
    durationMs: null
  };
}

function privacy(
  overrides: Partial<PrivacySettingsView> = {}
): PrivacySettingsView {
  return {
    strangersCanViewProfile: true,
    searchableByFangyuanNumber: true,
    globalGroupMuted: false,
    updatedAt: "2026-07-30T00:00:00.000Z",
    ...overrides
  };
}

class FakeProfileRepository {
  profileResult = projection();
  privacyResult = privacy();
  getProfileCalls: Array<[string, string]> = [];
  profileUpdates: Array<{ userId: string; patch: ProfilePatch }> = [];
  privacyUpdates: Array<{ userId: string; patch: PrivacyPatch }> = [];
  friendUserIds = [targetUserId];

  async getProfile(viewer: string, target: string): Promise<ProfileProjection> {
    this.getProfileCalls.push([viewer, target]);
    return this.profileResult;
  }

  async updateProfile(
    ownerUserId: string,
    patch: ProfilePatch
  ): Promise<ProfileProjection> {
    this.profileUpdates.push({ userId: ownerUserId, patch });
    return this.profileResult;
  }

  async getPrivacy(): Promise<PrivacySettingsView> {
    return this.privacyResult;
  }

  async updatePrivacy(
    ownerUserId: string,
    patch: PrivacyPatch
  ): Promise<PrivacySettingsView> {
    this.privacyUpdates.push({ userId: ownerUserId, patch });
    return this.privacyResult;
  }

  async listActiveFriendUserIds(): Promise<string[]> {
    return this.friendUserIds;
  }
}

class FakeMediaDeliveryService {
  calls: MediaDeliveryReference[] = [];

  async createView(reference: MediaDeliveryReference): Promise<MediaView> {
    this.calls.push(reference);
    return {
      mediaId: reference.mediaId,
      mediaType: reference.mediaType,
      status: reference.status,
      url: `https://media.example/${reference.mediaId}`,
      thumbnailUrl: null,
      coverUrl: null,
      width: reference.width,
      height: reference.height,
      durationMs: reference.durationMs,
      expiresAt: "2026-08-02T01:10:00.000Z"
    };
  }
}

function fixture(): {
  repository: FakeProfileRepository;
  delivery: FakeMediaDeliveryService;
  service: ProfileService;
} {
  const repository = new FakeProfileRepository();
  const delivery = new FakeMediaDeliveryService();
  return {
    repository,
    delivery,
    service: new ProfileService(
      repository as unknown as ProfileRepository,
      delivery as unknown as MediaDeliveryService
    )
  };
}

test("loads self and another user through the authenticated viewer", async () => {
  const { repository, service } = fixture();

  await service.getMine(userId);
  await service.getUser(userId, targetUserId);

  assert.deepEqual(repository.getProfileCalls, [
    [userId, userId],
    [userId, targetUserId]
  ]);
});

test("trims and validates editable profile fields", async () => {
  const { repository, service } = fixture();

  await service.updateMine({
    userId,
    idempotencyKey: "profile-update-1",
    body: {
      expectedVersion: 3,
      nickname: "  小桃子  ",
      gender: "female",
      signature: "  今天也要开心  "
    }
  });

  assert.deepEqual(repository.profileUpdates[0], {
    userId,
    patch: {
      expectedVersion: 3,
      nickname: "小桃子",
      gender: "female",
      customGender: null,
      signature: "今天也要开心"
    }
  });
});

test("keeps custom gender extensible but requires its label", async () => {
  const { service } = fixture();

  await assert.rejects(
    service.updateMine({
      userId,
      idempotencyKey: "profile-update-2",
      body: { expectedVersion: 1, gender: "custom" }
    }),
    (error: unknown) =>
      error instanceof ProfileDomainError &&
      error.code === "PROFILE_CUSTOM_GENDER_REQUIRED"
  );
});

test("passes explicit profile media bindings to the transactional repository", async () => {
  const { repository, service } = fixture();
  const avatarMediaId = "019f0000-0000-7000-8000-00000000000c";

  await service.updateMine({
    userId,
    idempotencyKey: "profile-update-3",
    body: {
      expectedVersion: 1,
      avatarMediaId,
      backgroundMediaId: null
    }
  });

  assert.deepEqual(repository.profileUpdates[0]?.patch, {
    expectedVersion: 1,
    avatarMediaId,
    backgroundMediaId: null
  });
});

test("delivers signed media views without exposing storage keys", async () => {
  const { repository, delivery, service } = fixture();
  const avatar = mediaReference("019f0000-0000-7000-8000-00000000000d");
  repository.profileResult = projection({ avatarReference: avatar });

  const result = await service.getMine(userId);

  assert.equal(result.avatar?.url, `https://media.example/${avatar.mediaId}`);
  assert.equal(result.background, null);
  assert.deepEqual(delivery.calls, [avatar]);
});

test("publishes a lightweight profile version event after persistence", async () => {
  const repository = new FakeProfileRepository();
  repository.profileResult = projection({ profileVersion: 8 });
  const delivery = new FakeMediaDeliveryService();
  const published: Array<{ userId: string; event: string; payload: unknown }> = [];
  const realtime = {
    async publish(target: string, event: string, payload: unknown) {
      published.push({ userId: target, event, payload });
    }
  };
  const service = new ProfileService(
    repository as unknown as ProfileRepository,
    delivery as unknown as MediaDeliveryService,
    realtime as unknown as RealtimeTransport
  );

  await service.updateMine({
    userId,
    idempotencyKey: "profile-update-realtime",
    body: { expectedVersion: 1, signature: "新的签名" }
  });

  assert.deepEqual(published, [
    {
      userId,
      event: "profile.updated",
      payload: { userId, profileVersion: 8 }
    },
    {
      userId: targetUserId,
      event: "profile.updated",
      payload: { userId, profileVersion: 8 }
    }
  ]);
});

test("updates only supplied privacy switches", async () => {
  const { repository, service } = fixture();

  await service.updatePrivacy({
    userId,
    idempotencyKey: "privacy-update-1",
    body: {
      strangersCanViewProfile: false,
      searchableByFangyuanNumber: true
    }
  });

  assert.deepEqual(repository.privacyUpdates[0], {
    userId,
    patch: {
      strangersCanViewProfile: false,
      searchableByFangyuanNumber: true
    }
  });
});

test("rejects empty privacy changes and missing idempotency keys", async () => {
  const { service } = fixture();

  assert.throws(
    () => service.updatePrivacy({
      userId,
      idempotencyKey: "privacy-update-2",
      body: {}
    }),
    (error: unknown) =>
      error instanceof ProfileDomainError &&
      error.code === "PRIVACY_UPDATE_EMPTY"
  );
  await assert.rejects(
    service.updateMine({
      userId,
      body: { expectedVersion: 1, nickname: "新昵称" }
    }),
    (error: unknown) =>
      error instanceof ProfileDomainError &&
      error.code === "IDEMPOTENCY_KEY_REQUIRED"
  );
});
