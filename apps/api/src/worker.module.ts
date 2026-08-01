import { Module } from "@nestjs/common";
import { DatabaseModule } from "./database/database.module.js";
import { MediaModule } from "./media/media.module.js";

@Module({ imports: [DatabaseModule, MediaModule] })
export class WorkerModule {}
