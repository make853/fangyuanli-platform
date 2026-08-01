import {
  Body,
  Controller,
  Get,
  Headers,
  HttpException,
  Param,
  Patch,
  UseGuards
} from "@nestjs/common";
import { randomUUID } from "node:crypto";
import { AccessTokenGuard } from "../auth/access-token.guard.js";
import { CurrentUserId } from "../auth/current-user.decorator.js";
import { ProfileService } from "./profile.service.js";
import { ProfileDomainError } from "./profile.types.js";

@Controller()
@UseGuards(AccessTokenGuard)
export class ProfileController {
  constructor(private readonly profiles: ProfileService) {}

  @Get("me")
  getMine(
    @CurrentUserId() userId: string,
    @Headers("x-request-id") requestId?: string
  ): Promise<unknown> {
    return this.respond(() => this.profiles.getMine(userId), requestId);
  }

  @Patch("me")
  updateMine(
    @CurrentUserId() userId: string,
    @Body() body: Record<string, unknown>,
    @Headers("idempotency-key") idempotencyKey?: string,
    @Headers("x-request-id") requestId?: string
  ): Promise<unknown> {
    return this.respond(
      () => this.profiles.updateMine({ userId, body, idempotencyKey }),
      requestId
    );
  }

  @Get("me/privacy")
  getPrivacy(
    @CurrentUserId() userId: string,
    @Headers("x-request-id") requestId?: string
  ): Promise<unknown> {
    return this.respond(() => this.profiles.getPrivacy(userId), requestId);
  }

  @Patch("me/privacy")
  updatePrivacy(
    @CurrentUserId() userId: string,
    @Body() body: Record<string, unknown>,
    @Headers("idempotency-key") idempotencyKey?: string,
    @Headers("x-request-id") requestId?: string
  ): Promise<unknown> {
    return this.respond(
      () => this.profiles.updatePrivacy({ userId, body, idempotencyKey }),
      requestId
    );
  }

  @Get("users/:userId")
  getUser(
    @CurrentUserId() viewerUserId: string,
    @Param("userId") targetUserId: string,
    @Headers("x-request-id") requestId?: string
  ): Promise<unknown> {
    return this.respond(
      () => this.profiles.getUser(viewerUserId, targetUserId),
      requestId
    );
  }

  private async respond<T>(
    action: () => Promise<T>,
    requestId?: string
  ): Promise<{ data: T; meta: { requestId: string; serverTime: string } }> {
    const resolvedRequestId = requestId?.trim() || randomUUID();
    try {
      return {
        data: await action(),
        meta: { requestId: resolvedRequestId, serverTime: new Date().toISOString() }
      };
    } catch (error) {
      if (error instanceof ProfileDomainError) {
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
