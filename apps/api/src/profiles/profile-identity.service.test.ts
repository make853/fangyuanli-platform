import assert from "node:assert/strict";
import test from "node:test";
import type { MediaDeliveryService } from "../media/media-delivery.service.js";
import type { ProfileRepository } from "./profile.repository.js";
import { ProfileIdentityService } from "./profile-identity.service.js";

test("batches identity projections and delivers avatar thumbnails once", async () => {
  const userId = "019f0000-0000-7000-8000-00000000000a";
  let requestedUserIds: string[] = [];
  const repository = {
    async getIdentityProjections(userIds: string[]) {
      requestedUserIds = userIds;
      return [
        {
          userId,
          displayName: "小桃子",
          profileVersion: 7,
          avatarReference: {
            mediaId: "019f0000-0000-7000-8000-00000000000b",
            mediaType: "image",
            status: "ready",
            displayObjectKey: "processed/avatar/display.webp",
            thumbnailObjectKey: "processed/avatar/thumbnail.webp",
            coverObjectKey: null,
            width: 512,
            height: 512,
            durationMs: null
          }
        }
      ];
    }
  };
  const delivery = {
    async createView(reference: { mediaId: string }) {
      return {
        mediaId: reference.mediaId,
        mediaType: "image",
        status: "ready",
        url: "https://media.example/avatar.webp",
        thumbnailUrl: "https://media.example/avatar-thumb.webp",
        coverUrl: null,
        width: 512,
        height: 512,
        durationMs: null,
        expiresAt: "2026-08-02T10:00:00.000Z"
      };
    }
  };
  const service = new ProfileIdentityService(
    repository as unknown as ProfileRepository,
    delivery as unknown as MediaDeliveryService
  );

  const identities = await service.getMany([userId, userId]);

  assert.deepEqual(requestedUserIds, [userId, userId]);
  assert.equal(identities.get(userId)?.profileVersion, 7);
  assert.equal(
    identities.get(userId)?.avatar?.thumbnailUrl,
    "https://media.example/avatar-thumb.webp"
  );
});
