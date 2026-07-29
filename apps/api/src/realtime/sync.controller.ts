import {
  Controller,
  Get,
  Headers,
  HttpException,
  Query,
  UseGuards
} from "@nestjs/common";
import { randomUUID } from "node:crypto";
import { AccessTokenGuard } from "../auth/access-token.guard.js";
import { CurrentUserId } from "../auth/current-user.decorator.js";
import { ConversationService } from "../conversations/conversation.service.js";
import {
  normalizeResumeCursor,
  RealtimeProtocolError
} from "./realtime-protocol.js";
import { RealtimeTransport } from "./realtime-transport.js";

@Controller(["sync", "api/v1/sync"])
@UseGuards(AccessTokenGuard)
export class SyncController {
  constructor(
    private readonly realtime: RealtimeTransport,
    private readonly conversations: ConversationService
  ) {}

  @Get("events")
  async events(
    @CurrentUserId() userId: string,
    @Query("afterCursor") rawCursor?: string,
    @Query("limit") rawLimit?: string,
    @Headers("x-request-id") requestId?: string
  ): Promise<unknown> {
    const resolvedRequestId = requestId?.trim() || randomUUID();
    try {
      const cursor = normalizeResumeCursor(rawCursor ?? "0-0")!;
      const limit = this.limit(rawLimit);
      const synced = await this.realtime.sync(userId, cursor, limit);
      if (!synced.expired) {
        return this.response(
          synced.events.map((event) => ({
            eventId: event.eventId,
            eventType: event.event,
            eventCursor: event.eventCursor,
            occurredAt: event.serverTime,
            payload: event.payload
          })),
          synced.latestCursor,
          synced.hasMore,
          resolvedRequestId
        );
      }

      const snapshot = await this.conversations.syncConversationSnapshots(userId);
      return this.response(
        snapshot.items.map((conversation) => ({
          eventId: randomUUID(),
          eventType: "conversation.snapshot",
          eventCursor: synced.latestCursor,
          occurredAt: new Date().toISOString(),
          payload: { conversation }
        })),
        synced.latestCursor,
        snapshot.hasMore,
        resolvedRequestId
      );
    } catch (error) {
      if (error instanceof RealtimeProtocolError) {
        throw new HttpException(
          {
            error: {
              code: error.code,
              message: error.message,
              requestId: resolvedRequestId
            }
          },
          400
        );
      }
      throw error;
    }
  }

  private limit(raw: string | undefined): number {
    const value = raw === undefined ? 100 : Number(raw);
    if (!Number.isSafeInteger(value) || value < 1 || value > 200) {
      throw new RealtimeProtocolError(
        "SYNC_LIMIT_INVALID",
        "同步数量应为1至200"
      );
    }
    return value;
  }

  private response(
    events: unknown[],
    latestCursor: string,
    hasMore: boolean,
    requestId: string
  ): unknown {
    return {
      data: { events, latestCursor, hasMore },
      meta: { requestId, serverTime: new Date().toISOString() }
    };
  }
}
