import type { WebSocket } from "ws";

export type ClientRealtimeEvent = {
  event: string;
  requestId: string;
  payload: Record<string, unknown>;
};

export type ServerRealtimeEvent = {
  event: string;
  requestId: string | null;
  eventId: string;
  eventCursor: string;
  serverTime: string;
  payload: Record<string, unknown>;
};

export type RealtimeConnection = {
  socket: WebSocket;
  userId: string;
  sessionId: string;
  deviceId: string;
  tokenVersion: number;
  ready: boolean;
  lastPongAt: number;
  pending: ServerRealtimeEvent[];
};

export type RealtimeResumeResult =
  | {
      status: "ready";
      resumed: boolean;
      latestCursor: string;
      events: ServerRealtimeEvent[];
    }
  | {
      status: "resync";
      reason: "cursorExpired" | "eventGap" | "serverRestart";
      latestCursor: string;
    };

export type RealtimeSyncResult = {
  events: ServerRealtimeEvent[];
  latestCursor: string;
  hasMore: boolean;
  expired: boolean;
};
