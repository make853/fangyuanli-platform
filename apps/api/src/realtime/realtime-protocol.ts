import { randomUUID } from "node:crypto";
import type {
  ClientRealtimeEvent,
  ServerRealtimeEvent
} from "./realtime.types.js";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const REDIS_CURSOR_PATTERN = /^\d+-\d+$/;

export class RealtimeProtocolError extends Error {
  constructor(
    public readonly code: string,
    message: string
  ) {
    super(message);
  }
}

export function parseClientEvent(raw: string): ClientRealtimeEvent {
  let value: unknown;
  try {
    value = JSON.parse(raw);
  } catch {
    throw new RealtimeProtocolError("REALTIME_JSON_INVALID", "实时事件不是有效JSON");
  }
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new RealtimeProtocolError("REALTIME_EVENT_INVALID", "实时事件格式无效");
  }
  const candidate = value as Record<string, unknown>;
  if (
    typeof candidate.event !== "string" ||
    !candidate.event ||
    typeof candidate.requestId !== "string" ||
    !UUID_PATTERN.test(candidate.requestId) ||
    !candidate.payload ||
    typeof candidate.payload !== "object" ||
    Array.isArray(candidate.payload)
  ) {
    throw new RealtimeProtocolError("REALTIME_EVENT_INVALID", "实时事件格式无效");
  }
  return {
    event: candidate.event,
    requestId: candidate.requestId,
    payload: candidate.payload as Record<string, unknown>
  };
}

export function normalizeResumeCursor(value: unknown): string | null {
  if (value === null) return null;
  if (typeof value !== "string" || !REDIS_CURSOR_PATTERN.test(value)) {
    throw new RealtimeProtocolError("REALTIME_CURSOR_INVALID", "实时游标无效");
  }
  return value;
}

export function compareRedisCursors(left: string, right: string): number {
  const [leftMs, leftSequence] = left.split("-").map(BigInt);
  const [rightMs, rightSequence] = right.split("-").map(BigInt);
  if (leftMs !== rightMs) return leftMs < rightMs ? -1 : 1;
  if (leftSequence === rightSequence) return 0;
  return leftSequence < rightSequence ? -1 : 1;
}

export function serverEvent(input: {
  event: string;
  eventCursor: string;
  payload: Record<string, unknown>;
  requestId?: string | null;
  eventId?: string;
  serverTime?: string;
}): ServerRealtimeEvent {
  return {
    event: input.event,
    requestId: input.requestId ?? null,
    eventId: input.eventId ?? randomUUID(),
    eventCursor: input.eventCursor,
    serverTime: input.serverTime ?? new Date().toISOString(),
    payload: input.payload
  };
}
