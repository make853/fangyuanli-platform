import { Module } from "@nestjs/common";
import { AuthModule } from "../auth/auth.module.js";
import { ConversationController } from "./conversation.controller.js";
import { ConversationRepository } from "./conversation.repository.js";
import { ConversationService } from "./conversation.service.js";

@Module({
  imports: [AuthModule],
  controllers: [ConversationController],
  providers: [ConversationRepository, ConversationService]
})
export class ConversationModule {}
