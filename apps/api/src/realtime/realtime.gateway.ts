import {
  Logger,
  OnModuleDestroy,
  OnModuleInit
} from "@nestjs/common";
import {
  OnGatewayConnection,
  OnGatewayDisconnect,
  WebSocketGateway
} from "@nestjs/websockets";
import { randomUUID } from "node:crypto";
import type { IncomingMessage } from "node:http";
import { WebSocket, type RawData } from "ws";
import { AuthRepository } from "../auth/auth.repository.js";
import { TokenService } from "../auth/token-service.js";
import { ConversationService } from "../conversations/conversation.service.js";
import { ConversationDomainError } from "../conversations/conversation.types.js";
import { RealtimeConnectionRegistry } from "./realtime-connection-registry.js";
import {
  normalizeResumeCursor,
  parseClientEvent,
  RealtimeProtocolError
} from "./realtime-protocol.js";
import { RealtimeTransport } from "./realtime-transport.js";
import type {
  ClientRealtimeEvent,
  RealtimeConnection
} from "./realtime.types.js";

const HEARTBEAT_INTERVAL_MS = 30_000;
const HEARTBEAT_TIMEOUT_MS = 75_000;

@WebSocketGateway({ path: "/ws/v1" })
export class RealtimeGateway
  implements
    OnGatewayConnection,
    OnGatewayDisconnect,
    OnModuleInit,
    OnModuleDestroy
{
  private readonly logger = new Logger(RealtimeGateway.name);
  private readonly messageChains = new WeakMap<WebSocket, Promise<void>>();
  private heartbeatTimer: NodeJS.Timeout | null = null;

  constructor(
    private readonly tokens: TokenService,
    private readonly authRepository: AuthRepository,
    private readonly conversations: ConversationService,
    private readonly transport: RealtimeTransport,
    private readonly connections: RealtimeConnectionRegistry
  ) {}

  onModuleInit(): void {
    this.heartbeatTimer = setInterval(() => {
      void this.heartbeat();
    }, HEARTBEAT_INTERVAL_MS);
    this.heartbeatTimer.unref();
  }

  onModuleDestroy(): void {
    if (this.heartbeatTimer) clearInterval(this.heartbeatTimer);
  }

  async handleConnection(
    socket: WebSocket,
    request: IncomingMessage
  ): Promise<void> {
    const earlyMessages: RawData[] = [];
    const bufferEarlyMessage = (data: RawData) => earlyMessages.push(data);
    socket.on("message", bufferEarlyMessage);
    try {
      const authorization = request.headers.authorization;
      const token =
        typeof authorization === "string"
          ? authorization.match(/^Bearer (.+)$/i)?.[1]
          : undefined;
      if (!token) throw new Error("Missing bearer token");
      const claims = await this.tokens.verifyAccessToken(token);
      if (!(await this.authRepository.isSessionActive(claims))) {
        throw new Error("Session is inactive");
      }
      const connection: RealtimeConnection = {
        socket,
        userId: claims.userId,
        sessionId: claims.sessionId,
        deviceId: claims.deviceId,
        tokenVersion: claims.tokenVersion,
        ready: false,
        lastPongAt: Date.now(),
        pending: []
      };
      this.connections.attach(connection);
      socket.off("message", bufferEarlyMessage);
      socket.on("message", (data) => this.enqueue(connection, data));
      for (const data of earlyMessages) this.enqueue(connection, data);
      socket.on("error", (error) =>
        this.logger.warn(`Realtime socket error: ${error.message}`)
      );
    } catch {
      socket.off("message", bufferEarlyMessage);
      socket.close(4401, "authentication required");
    }
  }

  handleDisconnect(socket: WebSocket): void {
    this.connections.detach(socket);
  }

  private enqueue(connection: RealtimeConnection, data: RawData): void {
    const previous = this.messageChains.get(connection.socket) ?? Promise.resolve();
    const next = previous
      .then(() => this.handleMessage(connection, data.toString()))
      .catch((error) => this.sendUnexpectedError(connection, error));
    this.messageChains.set(connection.socket, next);
  }

  private async handleMessage(
    connection: RealtimeConnection,
    raw: string
  ): Promise<void> {
    let event: ClientRealtimeEvent;
    try {
      event = parseClientEvent(raw);
    } catch (error) {
      await this.sendProtocolError(connection, error);
      return;
    }

    if (event.event === "session.resume") {
      if (connection.ready) {
        await this.sendError(
          connection,
          "REALTIME_SESSION_ALREADY_READY",
          "实时会话已经恢复",
          event.requestId
        );
        return;
      }
      await this.resume(connection, event);
      return;
    }
    if (
      !(await this.authRepository.isSessionActive({
        userId: connection.userId,
        sessionId: connection.sessionId,
        deviceId: connection.deviceId,
        tokenVersion: connection.tokenVersion
      }))
    ) {
      connection.socket.close(4401, "session expired");
      return;
    }
    if (!connection.ready) {
      await this.sendError(
        connection,
        "REALTIME_SESSION_NOT_READY",
        "请先恢复实时会话",
        event.requestId
      );
      return;
    }

    switch (event.event) {
      case "message.send":
        await this.sendMessage(connection, event);
        break;
      case "conversation.read":
        await this.advanceRead(connection, event);
        break;
      case "heartbeat.pong":
        connection.lastPongAt = Date.now();
        break;
      default:
        await this.sendError(
          connection,
          "REALTIME_EVENT_UNSUPPORTED",
          "当前不支持此实时事件",
          event.requestId
        );
    }
  }

  private async resume(
    connection: RealtimeConnection,
    event: ClientRealtimeEvent
  ): Promise<void> {
    try {
      const cursor = normalizeResumeCursor(event.payload.resumeCursor);
      const result = await this.transport.resume(connection.userId, cursor);
      if (result.status === "resync") {
        this.connections.sendConnection(
          connection,
          await this.transport.ephemeral(
            connection.userId,
            "session.resync_required",
            {
              reason: result.reason,
              syncEndpoint: "/api/v1/sync/events"
            },
            event.requestId
          )
        );
        this.connections.flush(connection, result.latestCursor);
        return;
      }
      this.connections.sendConnection(
        connection,
        await this.transport.ephemeral(
          connection.userId,
          "session.ready",
          {
            resumed: result.resumed,
            heartbeatIntervalSeconds: HEARTBEAT_INTERVAL_MS / 1000,
            latestCursor: result.latestCursor
          },
          event.requestId
        )
      );
      for (const replayed of result.events) {
        this.connections.sendConnection(connection, replayed);
      }
      this.connections.flush(connection, result.latestCursor);
    } catch (error) {
      await this.sendProtocolError(connection, error, event.requestId);
    }
  }

  private async sendMessage(
    connection: RealtimeConnection,
    event: ClientRealtimeEvent
  ): Promise<void> {
    try {
      const message = await this.conversations.sendMessage({
        userId: connection.userId,
        conversationId: event.payload.conversationId,
        body: event.payload,
        idempotencyKey: `ws:${event.requestId}`
      });
      this.connections.sendConnection(
        connection,
        await this.transport.ephemeral(
          connection.userId,
          "message.accepted",
          {
            clientMessageId: message.clientMessageId,
            messageId: message.messageId,
            conversationId: message.conversationId,
            sequence: message.sequence,
            createdAt: message.createdAt
          },
          event.requestId
        )
      );
    } catch (error) {
      if (error instanceof ConversationDomainError) {
        this.connections.sendConnection(
          connection,
          await this.transport.ephemeral(
            connection.userId,
            "message.rejected",
            {
              clientMessageId: event.payload.clientMessageId ?? null,
              error: { code: error.code, message: error.message }
            },
            event.requestId
          )
        );
        return;
      }
      throw error;
    }
  }

  private async advanceRead(
    connection: RealtimeConnection,
    event: ClientRealtimeEvent
  ): Promise<void> {
    try {
      await this.conversations.advanceReadCursor({
        userId: connection.userId,
        conversationId: event.payload.conversationId,
        lastReadSequence: event.payload.lastReadSequence,
        idempotencyKey: `ws:${event.requestId}`
      });
    } catch (error) {
      if (error instanceof ConversationDomainError) {
        await this.sendError(
          connection,
          error.code,
          error.message,
          event.requestId
        );
        return;
      }
      throw error;
    }
  }

  private async heartbeat(): Promise<void> {
    const now = Date.now();
    for (const connection of this.connections.all()) {
      if (now - connection.lastPongAt > HEARTBEAT_TIMEOUT_MS) {
        connection.socket.close(4408, "heartbeat timeout");
        continue;
      }
      if (!connection.ready) continue;
      this.connections.sendConnection(
        connection,
        await this.transport.ephemeral(
          connection.userId,
          "heartbeat.ping",
          { pingId: randomUUID() }
        )
      );
    }
  }

  private async sendProtocolError(
    connection: RealtimeConnection,
    error: unknown,
    requestId?: string
  ): Promise<void> {
    if (error instanceof RealtimeProtocolError) {
      await this.sendError(connection, error.code, error.message, requestId);
      return;
    }
    await this.sendUnexpectedError(connection, error);
  }

  private async sendUnexpectedError(
    connection: RealtimeConnection,
    error: unknown
  ): Promise<void> {
    this.logger.error(
      `Realtime handler failed: ${
        error instanceof Error ? error.message : String(error)
      }`
    );
    await this.sendError(
      connection,
      "REALTIME_INTERNAL_ERROR",
      "实时服务暂时不可用"
    );
  }

  private async sendError(
    connection: RealtimeConnection,
    code: string,
    message: string,
    requestId?: string
  ): Promise<void> {
    this.connections.sendConnection(
      connection,
      await this.transport.ephemeral(
        connection.userId,
        "realtime.error",
        { code, message },
        requestId ?? null
      )
    );
  }
}
