import {
  Body,
  Controller,
  Delete,
  Get,
  Headers,
  HttpCode,
  HttpException,
  Param,
  Patch,
  Post,
  Put,
  Query,
  UseGuards
} from "@nestjs/common";
import { randomUUID } from "node:crypto";
import { AccessTokenGuard } from "../auth/access-token.guard.js";
import { CurrentUserId } from "../auth/current-user.decorator.js";
import { RelationshipService } from "./relationship.service.js";
import { RelationshipDomainError } from "./relationship.types.js";

@Controller()
@UseGuards(AccessTokenGuard)
export class RelationshipController {
  constructor(private readonly relationships: RelationshipService) {}

  @Post("friend-requests")
  async createRequest(
    @CurrentUserId() userId: string,
    @Body() body: Record<string, unknown>,
    @Headers("idempotency-key") idempotencyKey?: string,
    @Headers("x-request-id") requestId?: string
  ): Promise<unknown> {
    return this.respond(
      () =>
        this.relationships.createRequest({
          senderUserId: userId,
          targetUserId: body.targetUserId,
          applicationNote: body.applicationNote,
          idempotencyKey
        }),
      requestId
    );
  }

  @Get("friend-requests")
  async listRequests(
    @CurrentUserId() userId: string,
    @Query("direction") direction?: string,
    @Query("status") status?: string,
    @Query("cursor") cursor?: string,
    @Query("limit") limit?: string,
    @Headers("x-request-id") requestId?: string
  ): Promise<unknown> {
    return this.respond(
      () =>
        this.relationships.listRequests({
          userId,
          direction,
          status,
          cursor,
          limit
        }),
      requestId
    );
  }

  @Post("friend-requests/:requestId/decision")
  @HttpCode(200)
  async decideRequest(
    @CurrentUserId() userId: string,
    @Param("requestId") friendRequestId: string,
    @Body() body: Record<string, unknown>,
    @Headers("idempotency-key") idempotencyKey?: string,
    @Headers("x-request-id") requestId?: string
  ): Promise<unknown> {
    return this.respond(
      () =>
        this.relationships.decideRequest({
          receiverUserId: userId,
          requestId: friendRequestId,
          decision: body.decision,
          idempotencyKey
        }),
      requestId
    );
  }

  @Get("friends")
  async listFriends(
    @CurrentUserId() userId: string,
    @Query("keyword") keyword?: string,
    @Query("cursor") cursor?: string,
    @Query("limit") limit?: string,
    @Headers("x-request-id") requestId?: string
  ): Promise<unknown> {
    return this.respond(
      () => this.relationships.listFriends({ userId, keyword, cursor, limit }),
      requestId
    );
  }

  @Patch("friends/:friendUserId/settings")
  async updateSettings(
    @CurrentUserId() userId: string,
    @Param("friendUserId") friendUserId: string,
    @Body() body: Record<string, unknown>,
    @Headers("idempotency-key") idempotencyKey?: string,
    @Headers("x-request-id") requestId?: string
  ): Promise<unknown> {
    return this.respond(
      () =>
        this.relationships.updateFriendSettings({
          ownerUserId: userId,
          friendUserId,
          body,
          idempotencyKey
        }),
      requestId
    );
  }

  @Delete("friends/:friendUserId")
  @HttpCode(204)
  async deleteFriend(
    @CurrentUserId() userId: string,
    @Param("friendUserId") friendUserId: string,
    @Headers("idempotency-key") idempotencyKey?: string
  ): Promise<void> {
    await this.handle(() =>
      this.relationships.deleteFriend({ userId, friendUserId, idempotencyKey })
    );
  }

  @Get("blocks")
  async listBlocks(
    @CurrentUserId() userId: string,
    @Query("cursor") cursor?: string,
    @Query("limit") limit?: string,
    @Headers("x-request-id") requestId?: string
  ): Promise<unknown> {
    return this.respond(
      () => this.relationships.listBlocks({ blockerUserId: userId, cursor, limit }),
      requestId
    );
  }

  @Put("blocks/:targetUserId")
  async block(
    @CurrentUserId() userId: string,
    @Param("targetUserId") targetUserId: string,
    @Body() body: Record<string, unknown>,
    @Headers("idempotency-key") idempotencyKey?: string,
    @Headers("x-request-id") requestId?: string
  ): Promise<unknown> {
    return this.respond(
      () =>
        this.relationships.block({
          blockerUserId: userId,
          targetUserId,
          reasonCode: body?.reasonCode,
          idempotencyKey
        }),
      requestId
    );
  }

  @Delete("blocks/:targetUserId")
  async unblock(
    @CurrentUserId() userId: string,
    @Param("targetUserId") targetUserId: string,
    @Headers("idempotency-key") idempotencyKey?: string,
    @Headers("x-request-id") requestId?: string
  ): Promise<unknown> {
    return this.respond(
      () =>
        this.relationships.unblock({
          blockerUserId: userId,
          targetUserId,
          idempotencyKey
        }),
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
      this.throwHttp(error, resolvedRequestId);
    }
  }

  private async handle(action: () => Promise<void>): Promise<void> {
    try {
      await action();
    } catch (error) {
      this.throwHttp(error);
    }
  }

  private throwHttp(error: unknown, requestId?: string): never {
    if (error instanceof RelationshipDomainError) {
      throw new HttpException(
        {
          error: {
            code: error.code,
            message: error.message,
            requestId: requestId || randomUUID()
          }
        },
        error.status
      );
    }
    throw error;
  }
}
