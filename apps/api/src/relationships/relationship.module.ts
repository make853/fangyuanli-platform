import { Module } from "@nestjs/common";
import { AuthModule } from "../auth/auth.module.js";
import { ProfileModule } from "../profiles/profile.module.js";
import { RelationshipController } from "./relationship.controller.js";
import { RelationshipRepository } from "./relationship.repository.js";
import { RelationshipService } from "./relationship.service.js";
import { RequestHasher } from "./request-hasher.js";

@Module({
  imports: [AuthModule, ProfileModule],
  controllers: [RelationshipController],
  providers: [RelationshipRepository, RelationshipService, RequestHasher]
})
export class RelationshipModule {}
