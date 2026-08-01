import { Module } from "@nestjs/common";
import { AuthModule } from "../auth/auth.module.js";
import { RequestHasher } from "../relationships/request-hasher.js";
import { MediaController } from "./media.controller.js";
import { MediaRepository } from "./media.repository.js";
import { MediaService } from "./media.service.js";
import {
  CosObjectStorageAdapter,
  ObjectStorageAdapter
} from "./media.storage.js";

@Module({
  imports: [AuthModule],
  controllers: [MediaController],
  providers: [
    MediaRepository,
    MediaService,
    RequestHasher,
    {
      provide: ObjectStorageAdapter,
      useFactory: () => new CosObjectStorageAdapter()
    }
  ]
})
export class MediaModule {}
