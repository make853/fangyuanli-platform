import { Module } from "@nestjs/common";
import { AuthModule } from "../auth/auth.module.js";
import { MediaModule } from "../media/media.module.js";
import { ProfileController } from "./profile.controller.js";
import { ProfileIdentityService } from "./profile-identity.service.js";
import { ProfileRepository } from "./profile.repository.js";
import { ProfileService } from "./profile.service.js";

@Module({
  imports: [AuthModule, MediaModule],
  controllers: [ProfileController],
  providers: [ProfileRepository, ProfileIdentityService, ProfileService],
  exports: [ProfileIdentityService]
})
export class ProfileModule {}
