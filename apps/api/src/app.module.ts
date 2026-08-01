import { Module } from "@nestjs/common";
import { AuthModule } from "./auth/auth.module.js";
import { ConversationModule } from "./conversations/conversation.module.js";
import { HealthController } from "./health.controller.js";
import { ProfileModule } from "./profiles/profile.module.js";
import { RelationshipModule } from "./relationships/relationship.module.js";

@Module({
  imports: [AuthModule, RelationshipModule, ConversationModule, ProfileModule],
  controllers: [HealthController]
})
export class AppModule {}
