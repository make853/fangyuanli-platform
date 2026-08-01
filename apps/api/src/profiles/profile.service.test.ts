import assert from "node:assert/strict";
import test from "node:test";
import type { ProfileRepository } from "./profile.repository.js";
import { ProfileService } from "./profile.service.js";
import {
  ProfileDomainError,
  type PrivacyPatch,
  type PrivacySettingsView,
  type ProfilePatch,
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
  profileResult = profile();
  privacyResult = privacy();
  getProfileCalls: Array<[string, string]> = [];
  profileUpdates: Array<{ userId: string; patch: ProfilePatch }> = [];
  privacyUpdates: Array<{ userId: string; patch: PrivacyPatch }> = [];

  async getProfile(viewer: string, target: string): Promise<ProfileView> {
    this.getProfileCalls.push([viewer, target]);
    return this.profileResult;
  }

  async updateProfile(
    ownerUserId: string,
    patch: ProfilePatch
  ): Promise<ProfileView> {
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
}

function fixture(): {
  repository: FakeProfileRepository;
  service: ProfileService;
} {
  const repository = new FakeProfileRepository();
  return {
    repository,
    service: new ProfileService(repository as unknown as ProfileRepository)
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

  assert.throws(
    () => service.updateMine({
      userId,
      idempotencyKey: "profile-update-2",
      body: { expectedVersion: 1, gender: "custom" }
    }),
    (error: unknown) =>
      error instanceof ProfileDomainError &&
      error.code === "PROFILE_CUSTOM_GENDER_REQUIRED"
  );
});

test("keeps profile media closed until its upload pipeline exists", async () => {
  const { service } = fixture();

  assert.throws(
    () => service.updateMine({
      userId,
      idempotencyKey: "profile-update-3",
      body: { expectedVersion: 1, avatarMediaId: null }
    }),
    (error: unknown) =>
      error instanceof ProfileDomainError &&
      error.code === "PROFILE_MEDIA_NOT_READY"
  );
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
  assert.throws(
    () => service.updateMine({
      userId,
      body: { expectedVersion: 1, nickname: "新昵称" }
    }),
    (error: unknown) =>
      error instanceof ProfileDomainError &&
      error.code === "IDEMPOTENCY_KEY_REQUIRED"
  );
});
