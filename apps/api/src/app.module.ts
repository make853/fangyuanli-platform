import { Module } from "@nestjs/common";
import { AuthModule } from "./auth/auth.module.js";
import { HealthController } from "./health.controller.js";
import { RelationshipModule } from "./relationships/relationship.module.js";

@Module({
  imports: [AuthModule, RelationshipModule],
  controllers: [HealthController]
})
export class AppModule {}
