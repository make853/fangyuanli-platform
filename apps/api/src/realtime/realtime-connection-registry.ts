import { Injectable } from "@nestjs/common";
import { WebSocket } from "ws";
import type {
  RealtimeConnection,
  ServerRealtimeEvent
} from "./realtime.types.js";
import { compareRedisCursors } from "./realtime-protocol.js";

@Injectable()
export class RealtimeConnectionRegistry {
  private readonly byUser = new Map<string, Set<RealtimeConnection>>();
  private readonly bySocket = new WeakMap<WebSocket, RealtimeConnection>();

  attach(connection: RealtimeConnection): void {
    const connections = this.byUser.get(connection.userId) ?? new Set();
    connections.add(connection);
    this.byUser.set(connection.userId, connections);
    this.bySocket.set(connection.socket, connection);
  }

  detach(socket: WebSocket): void {
    const connection = this.bySocket.get(socket);
    if (!connection) return;
    this.bySocket.delete(socket);
    const connections = this.byUser.get(connection.userId);
    connections?.delete(connection);
    if (!connections?.size) this.byUser.delete(connection.userId);
  }

  get(socket: WebSocket): RealtimeConnection | undefined {
    return this.bySocket.get(socket);
  }

  sendConnection(
    connection: RealtimeConnection,
    event: ServerRealtimeEvent
  ): boolean {
    if (connection.socket.readyState !== WebSocket.OPEN) return false;
    connection.socket.send(JSON.stringify(event));
    return true;
  }

  sendUser(userId: string, event: ServerRealtimeEvent): number {
    let delivered = 0;
    for (const connection of this.byUser.get(userId) ?? []) {
      if (!connection.ready) {
        connection.pending.push(event);
        if (connection.pending.length > 500) {
          connection.socket.close(4409, "realtime event gap");
        }
      } else if (this.sendConnection(connection, event)) {
        delivered += 1;
      }
    }
    return delivered;
  }

  flush(connection: RealtimeConnection, afterCursor: string): void {
    const pending = connection.pending
      .filter((event) => compareRedisCursors(event.eventCursor, afterCursor) > 0)
      .sort((left, right) =>
        compareRedisCursors(left.eventCursor, right.eventCursor)
      );
    connection.pending = [];
    connection.ready = true;
    for (const event of pending) this.sendConnection(connection, event);
  }

  all(): RealtimeConnection[] {
    return [...this.byUser.values()].flatMap((connections) => [
      ...connections
    ]);
  }
}
