import { Module } from "@nestjs/common";
import { AuthModule } from "../auth/auth.module.js";
import { RealtimeInfrastructureModule } from "../realtime/realtime-infrastructure.module.js";
import { RealtimeGateway } from "../realtime/realtime.gateway.js";
import { SyncController } from "../realtime/sync.controller.js";
import { ConversationController } from "./conversation.controller.js";
import { ConversationRepository } from "./conversation.repository.js";
import { ConversationService } from "./conversation.service.js";

@Module({
  imports: [AuthModule, RealtimeInfrastructureModule],
  controllers: [ConversationController, SyncController],
  providers: [ConversationRepository, ConversationService, RealtimeGateway],
  exports: [ConversationService]
})
export class ConversationModule {}
