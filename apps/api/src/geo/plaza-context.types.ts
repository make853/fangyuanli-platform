import type { Gcj02Point } from "./location-context.js";

export type MotionState =
  | "stationary"
  | "walking"
  | "running"
  | "driving"
  | "unknown";

export type GeoContextRequest = Gcj02Point & {
  accuracyMeters: number;
  capturedAt: Date;
  motionState: MotionState;
};

export type PlazaGridVersion = {
  id: string;
  version: number;
  coordinateSystem: "gcj02";
  projectionKey: "gcj02-web-mercator-v1";
  sideLengthMeters: number;
};

export type PlazaCell = {
  gridX: number;
  gridY: number;
};

export type PlazaProjection = PlazaCell & {
  plazaId: string;
  conversationId: string;
  name: string;
  latestSequence: number;
  lastReadSequence: number;
  unreadCount: number;
  firstUnreadSequence: number | null;
  notificationMode: "normal" | "muted";
};

export type PlazaAnchor = {
  userId: string;
  gridVersionId: string;
  point: Gcj02Point;
  plazaIds: string[];
  pendingPlazaIds: string[] | null;
  pendingConfirmationCount: number;
  pendingFirstSeenAt: Date | null;
  lastAccuracyMeters: number;
  anchorPolicyVersion: number;
  createdAt: Date;
  lastConfirmedAt: Date;
  updatedAt: Date;
};

export type PlazaSummary = {
  plazaId: string;
  conversationId: string;
  name: string;
  relation: "main" | "adjacent";
  canView: true;
  canSpeak: true;
  unread: {
    count: number;
    appearance: "none" | "red" | "gray";
    firstUnreadSequence: number | null;
  };
};

export type GeoContextResult = {
  locationContextToken: string;
  expiresAt: string;
  anchor: {
    radiusMeters: number;
    isReused: boolean;
    recalculationPending: boolean;
  };
  plazas: PlazaSummary[];
};

export class GeoDomainError extends Error {
  constructor(
    public readonly code: string,
    message: string,
    public readonly status: number
  ) {
    super(message);
  }
}
