import { Module } from "@nestjs/common";
import { AuthModule } from "../auth/auth.module.js";
import { GeoModule } from "../geo/geo.module.js";
import { ProfileModule } from "../profiles/profile.module.js";
import { RealtimeInfrastructureModule } from "../realtime/realtime-infrastructure.module.js";
import { RealtimeGateway } from "../realtime/realtime.gateway.js";
import { SyncController } from "../realtime/sync.controller.js";
import { ConversationController } from "./conversation.controller.js";
import { ConversationAccessService } from "./conversation-access.service.js";
import { ConversationRepository } from "./conversation.repository.js";
import { ConversationService } from "./conversation.service.js";

@Module({
  imports: [AuthModule, GeoModule, ProfileModule, RealtimeInfrastructureModule],
  controllers: [ConversationController, SyncController],
  providers: [
    ConversationAccessService,
    ConversationRepository,
    ConversationService,
    RealtimeGateway
  ],
  exports: [ConversationService]
})
export class ConversationModule {}
