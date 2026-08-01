import { Module } from "@nestjs/common";
import { AuthModule } from "./auth/auth.module.js";
import { ConversationModule } from "./conversations/conversation.module.js";
import { DatabaseModule } from "./database/database.module.js";
import { HealthController } from "./health.controller.js";
import { MediaModule } from "./media/media.module.js";
import { ProfileModule } from "./profiles/profile.module.js";
import { RelationshipModule } from "./relationships/relationship.module.js";

@Module({
  imports: [
    DatabaseModule,
    AuthModule,
    RelationshipModule,
    ConversationModule,
    ProfileModule,
    MediaModule
  ],
  controllers: [HealthController]
})
export class AppModule {}
