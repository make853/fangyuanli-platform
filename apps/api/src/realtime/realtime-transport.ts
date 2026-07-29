import {
  Inject,
  Injectable,
  OnApplicationBootstrap
} from "@nestjs/common";
import { RealtimeConnectionRegistry } from "./realtime-connection-registry.js";
import { RealtimeEventStore } from "./realtime-event-store.js";
import { serverEvent } from "./realtime-protocol.js";
import type {
  RealtimeResumeResult,
  RealtimeSyncResult,
  ServerRealtimeEvent
} from "./realtime.types.js";

@Injectable()
export class RealtimeTransport implements OnApplicationBootstrap {
  constructor(
    @Inject(RealtimeEventStore)
    private readonly store: RealtimeEventStore,
    @Inject(RealtimeConnectionRegistry)
    private readonly connections: RealtimeConnectionRegistry
  ) {}

  onApplicationBootstrap(): void {
    this.store.listen((userId, event) => {
      this.connections.sendUser(userId, event);
    });
  }

  publish(
    userId: string,
    event: string,
    payload: Record<string, unknown>,
    requestId?: string | null
  ): Promise<ServerRealtimeEvent> {
    return this.store.append({ userId, event, payload, requestId });
  }

  resume(userId: string, cursor: string | null): Promise<RealtimeResumeResult> {
    return this.store.resume(userId, cursor);
  }

  sync(
    userId: string,
    cursor: string,
    limit: number
  ): Promise<RealtimeSyncResult> {
    return this.store.sync(userId, cursor, limit);
  }

  async ephemeral(
    userId: string,
    event: string,
    payload: Record<string, unknown>,
    requestId?: string | null
  ): Promise<ServerRealtimeEvent> {
    return serverEvent({
      event,
      eventCursor: await this.store.latestCursor(userId),
      payload,
      requestId
    });
  }
}
