import { Injectable } from "@nestjs/common";
import { MediaDeliveryService } from "../media/media-delivery.service.js";
import { MediaDeliveryError } from "../media/media.types.js";
import { ProfileRepository } from "./profile.repository.js";
import {
  ProfileDomainError,
  type UserIdentityView
} from "./profile.types.js";

@Injectable()
export class ProfileIdentityService {
  constructor(
    private readonly repository: ProfileRepository,
    private readonly mediaDelivery: MediaDeliveryService
  ) {}

  async getMany(userIds: string[]): Promise<Map<string, UserIdentityView>> {
    const projections = await this.repository.getIdentityProjections(userIds);
    try {
      const views = await Promise.all(
        projections.map(async (projection) => ({
          userId: projection.userId,
          displayName: projection.displayName,
          profileVersion: projection.profileVersion,
          avatar: projection.avatarReference
            ? await this.mediaDelivery.createView(projection.avatarReference)
            : null
        }))
      );
      return new Map(views.map((view) => [view.userId, view]));
    } catch (error) {
      if (error instanceof MediaDeliveryError) {
        throw new ProfileDomainError(error.code, error.message, 503);
      }
      throw error;
    }
  }
}
