import {
  Injectable,
  Logger,
  OnApplicationBootstrap,
  OnApplicationShutdown
} from "@nestjs/common";
import { randomUUID } from "node:crypto";
import { createClient, type RedisClientType } from "redis";
import {
  compareRedisCursors,
  serverEvent
} from "./realtime-protocol.js";
import type {
  RealtimeResumeResult,
  RealtimeSyncResult,
  ServerRealtimeEvent
} from "./realtime.types.js";

const EVENT_TTL_SECONDS = 7 * 24 * 60 * 60;
const STREAM_MAX_LENGTH = 10_000;
const RESUME_LIMIT = 500;

type EventListener = (userId: string, event: ServerRealtimeEvent) => void;

function redisUrl(): string {
  const value = process.env.REDIS_URL?.trim();
  if (!value) throw new Error("REDIS_URL is required");
  return value;
}

@Injectable()
export class RealtimeEventStore
  implements OnApplicationBootstrap, OnApplicationShutdown
{
  private readonly logger = new Logger(RealtimeEventStore.name);
  private readonly command: RedisClientType | null;
  private readonly subscriber: RedisClientType | null;
  private listener: EventListener | null = null;

  constructor() {
    if (process.env.REALTIME_ENABLED === "false") {
      this.command = null;
      this.subscriber = null;
      return;
    }
    const options = { url: redisUrl() };
    this.command = createClient(options);
    this.subscriber = createClient(options);
    this.command.on("error", (error) =>
      this.logger.error(`Redis command connection error: ${error.message}`)
    );
    this.subscriber.on("error", (error) =>
      this.logger.error(`Redis subscriber connection error: ${error.message}`)
    );
  }

  async onApplicationBootstrap(): Promise<void> {
    if (!this.command || !this.subscriber) return;
    await Promise.all([this.command.connect(), this.subscriber.connect()]);
    await this.subscriber.pSubscribe("realtime:user:*", (message, channel) => {
      const userId = channel.slice("realtime:user:".length);
      try {
        this.listener?.(userId, JSON.parse(message) as ServerRealtimeEvent);
      } catch (error) {
        this.logger.error(
          `Invalid realtime pubsub payload: ${
            error instanceof Error ? error.message : String(error)
          }`
        );
      }
    });
  }

  async onApplicationShutdown(): Promise<void> {
    if (!this.command || !this.subscriber) return;
    await Promise.allSettled([
      this.subscriber.isOpen ? this.subscriber.quit() : Promise.resolve(),
      this.command.isOpen ? this.command.quit() : Promise.resolve()
    ]);
  }

  listen(listener: EventListener): void {
    this.listener = listener;
  }

  async append(input: {
    userId: string;
    event: string;
    payload: Record<string, unknown>;
    requestId?: string | null;
  }): Promise<ServerRealtimeEvent> {
    const eventId = randomUUID();
    const serverTime = new Date().toISOString();
    const key = this.streamKey(input.userId);
    const command = this.requireCommand();
    const cursor = await command.xAdd(
      key,
      "*",
      {
        event: input.event,
        eventId,
        requestId: input.requestId ?? "",
        serverTime,
        payload: JSON.stringify(input.payload)
      },
      { TRIM: { strategy: "MAXLEN", strategyModifier: "~", threshold: STREAM_MAX_LENGTH } }
    );
    await command.expire(key, EVENT_TTL_SECONDS);
    const envelope = serverEvent({
      event: input.event,
      eventCursor: cursor,
      payload: input.payload,
      requestId: input.requestId ?? null,
      eventId,
      serverTime
    });
    await command.publish(this.channel(input.userId), JSON.stringify(envelope));
    return envelope;
  }

  async latestCursor(userId: string): Promise<string> {
    const latest = await this.requireCommand().xRevRange(
      this.streamKey(userId),
      "+",
      "-",
      { COUNT: 1 }
    );
    return latest[0]?.id ?? "0-0";
  }

  async resume(
    userId: string,
    cursor: string | null
  ): Promise<RealtimeResumeResult> {
    const key = this.streamKey(userId);
    const latestCursor = await this.latestCursor(userId);
    if (cursor === null) {
      return {
        status: "ready",
        resumed: false,
        latestCursor,
        events: []
      };
    }
    if (latestCursor === "0-0") {
      return cursor === "0-0"
        ? {
            status: "ready",
            resumed: true,
            latestCursor,
            events: []
          }
        : {
            status: "resync",
            reason: "serverRestart",
            latestCursor
          };
    }
    const command = this.requireCommand();
    const earliest = await command.xRange(key, "-", "+", { COUNT: 1 });
    if (
      earliest[0] &&
      cursor !== "0-0" &&
      compareRedisCursors(cursor, earliest[0].id) < 0
    ) {
      return {
        status: "resync",
        reason: "cursorExpired",
        latestCursor
      };
    }
    const entries = await command.xRange(
      key,
      `(${cursor}`,
      "+",
      { COUNT: RESUME_LIMIT + 1 }
    );
    if (entries.length > RESUME_LIMIT) {
      return {
        status: "resync",
        reason: "eventGap",
        latestCursor
      };
    }
    return {
      status: "ready",
      resumed: true,
      latestCursor,
      events: entries.map((entry) =>
        serverEvent({
          event: entry.message.event,
          eventCursor: entry.id,
          eventId: entry.message.eventId,
          requestId: entry.message.requestId || null,
          serverTime: entry.message.serverTime,
          payload: JSON.parse(entry.message.payload) as Record<string, unknown>
        })
      )
    };
  }

  async sync(
    userId: string,
    cursor: string,
    limit: number
  ): Promise<RealtimeSyncResult> {
    const key = this.streamKey(userId);
    const latestCursor = await this.latestCursor(userId);
    if (latestCursor === "0-0") {
      return { events: [], latestCursor, hasMore: false, expired: false };
    }
    const command = this.requireCommand();
    const earliest = await command.xRange(key, "-", "+", { COUNT: 1 });
    if (
      earliest[0] &&
      cursor !== "0-0" &&
      compareRedisCursors(cursor, earliest[0].id) < 0
    ) {
      return { events: [], latestCursor, hasMore: false, expired: true };
    }
    const entries = await command.xRange(key, `(${cursor}`, "+", {
      COUNT: limit + 1
    });
    const selected = entries.slice(0, limit);
    return {
      events: selected.map((entry) =>
        serverEvent({
          event: entry.message.event,
          eventCursor: entry.id,
          eventId: entry.message.eventId,
          requestId: entry.message.requestId || null,
          serverTime: entry.message.serverTime,
          payload: JSON.parse(entry.message.payload) as Record<string, unknown>
        })
      ),
      latestCursor,
      hasMore: entries.length > limit,
      expired: false
    };
  }

  private streamKey(userId: string): string {
    return `realtime:events:${userId}`;
  }

  private channel(userId: string): string {
    return `realtime:user:${userId}`;
  }

  private requireCommand(): RedisClientType {
    if (!this.command) throw new Error("Realtime transport is disabled");
    return this.command;
  }
}
