import {
  Body,
  Controller,
  Get,
  Headers,
  HttpException,
  Param,
  Post,
  Put,
  Query,
  UseGuards
} from "@nestjs/common";
import { randomUUID } from "node:crypto";
import { AccessTokenGuard } from "../auth/access-token.guard.js";
import { CurrentUserId } from "../auth/current-user.decorator.js";
import { ConversationService } from "./conversation.service.js";
import { ConversationDomainError } from "./conversation.types.js";

@Controller("conversations")
@UseGuards(AccessTokenGuard)
export class ConversationController {
  constructor(private readonly conversations: ConversationService) {}

  @Get()
  list(
    @CurrentUserId() userId: string,
    @Query("cursor") cursor?: string,
    @Query("limit") limit?: string,
    @Headers("x-request-id") requestId?: string
  ): Promise<unknown> {
    return this.respond(
      () => this.conversations.listConversations({ userId, cursor, limit }),
      requestId
    );
  }

  @Get(":conversationId")
  detail(
    @CurrentUserId() userId: string,
    @Param("conversationId") conversationId: string,
    @Headers("x-request-id") requestId?: string
  ): Promise<unknown> {
    return this.respond(
      () => this.conversations.getConversation(userId, conversationId),
      requestId
    );
  }

  @Get(":conversationId/messages")
  messages(
    @CurrentUserId() userId: string,
    @Param("conversationId") conversationId: string,
    @Query("beforeSequence") beforeSequence?: string,
    @Query("afterSequence") afterSequence?: string,
    @Query("anchorSequence") anchorSequence?: string,
    @Query("limit") limit?: string,
    @Headers("x-request-id") requestId?: string
  ): Promise<unknown> {
    return this.respond(
      () =>
        this.conversations.listMessages({
          userId,
          conversationId,
          beforeSequence,
          afterSequence,
          anchorSequence,
          limit
        }),
      requestId
    );
  }

  @Post(":conversationId/messages")
  send(
    @CurrentUserId() userId: string,
    @Param("conversationId") conversationId: string,
    @Body() body: Record<string, unknown>,
    @Headers("idempotency-key") idempotencyKey?: string,
    @Headers("x-request-id") requestId?: string
  ): Promise<unknown> {
    return this.respond(
      () =>
        this.conversations.sendMessage({
          userId,
          conversationId,
          body,
          idempotencyKey
        }),
      requestId
    );
  }

  @Put(":conversationId/read-cursor")
  read(
    @CurrentUserId() userId: string,
    @Param("conversationId") conversationId: string,
    @Body() body: Record<string, unknown>,
    @Headers("idempotency-key") idempotencyKey?: string,
    @Headers("x-request-id") requestId?: string
  ): Promise<unknown> {
    return this.respond(
      () =>
        this.conversations.advanceReadCursor({
          userId,
          conversationId,
          lastReadSequence: body.lastReadSequence,
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
        meta: {
          requestId: resolvedRequestId,
          serverTime: new Date().toISOString()
        }
      };
    } catch (error) {
      if (error instanceof ConversationDomainError) {
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
