import {
  Body,
  Controller,
  Get,
  Headers,
  HttpException,
  Param,
  Post,
  UseGuards
} from "@nestjs/common";
import { randomUUID } from "node:crypto";
import { AccessTokenGuard } from "../auth/access-token.guard.js";
import { CurrentUserId } from "../auth/current-user.decorator.js";
import { MediaService } from "./media.service.js";
import { MediaDomainError } from "./media.types.js";

@Controller("media")
@UseGuards(AccessTokenGuard)
export class MediaController {
  constructor(private readonly media: MediaService) {}

  @Post("uploads")
  createUpload(
    @CurrentUserId() userId: string,
    @Body() body: Record<string, unknown>,
    @Headers("idempotency-key") idempotencyKey?: string,
    @Headers("x-request-id") requestId?: string
  ): Promise<unknown> {
    return this.respond(
      () => this.media.createUpload({ userId, body, idempotencyKey }),
      requestId
    );
  }

  @Post("uploads/:uploadId/complete")
  completeUpload(
    @CurrentUserId() userId: string,
    @Param("uploadId") uploadId: string,
    @Body() body: Record<string, unknown>,
    @Headers("idempotency-key") idempotencyKey?: string,
    @Headers("x-request-id") requestId?: string
  ): Promise<unknown> {
    return this.respond(
      () =>
        this.media.completeUpload({
          userId,
          uploadId,
          body,
          idempotencyKey
        }),
      requestId
    );
  }

  @Get(":mediaId")
  getMedia(
    @CurrentUserId() userId: string,
    @Param("mediaId") mediaId: string,
    @Headers("x-request-id") requestId?: string
  ): Promise<unknown> {
    return this.respond(() => this.media.getMedia(userId, mediaId), requestId);
  }

  private async respond<T>(
    action: () => Promise<T>,
    requestId?: string
  ): Promise<{ data: T; meta: { requestId: string; serverTime: string } }> {
    const resolvedRequestId = requestId?.trim() || randomUUID();
    try {
      return {
        data: await action(),
        meta: {
          requestId: resolvedRequestId,
          serverTime: new Date().toISOString()
        }
      };
    } catch (error) {
      if (error instanceof MediaDomainError) {
        throw new HttpException(
          {
            error: {
              code: error.code,
              message: error.message,
              requestId: resolvedRequestId
            }
          },
          error.status
        );
      }
      throw error;
    }
  }
}
