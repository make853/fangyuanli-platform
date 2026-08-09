import type { Gcj02Point } from "./location-context.js";

export type PlazaNamingSource =
  | "landmark"
  | "venue"
  | "road"
  | "community";

export type PlazaNamingKind =
  | "public_square"
  | "transit"
  | "culture_scenic"
  | "public_service"
  | "commercial_landmark"
  | "community"
  | "village"
  | "area"
  | "road";

export type PlazaNameCandidate = {
  name: string;
  source: PlazaNamingSource;
  kind: PlazaNamingKind;
  score: number;
  /** Provider coordinate used by the domain boundary policy. */
  point?: Gcj02Point;
  /** Optional provider audit metadata; never used as plaza identity. */
  provider?: "amap";
  providerPlaceId?: string;
};

/**
 * Persisted policy version. Increment only when existing automatic names should
 * be reconsidered; plaza identity and conversation identity never change.
 */
export const PLAZA_NAMING_POLICY_VERSION = 7;

/** External map boundary. Implementations must never expose provider IDs as names. */
export abstract class PlazaNamingProvider {
  abstract isConfigured(): boolean;
  abstract candidates(point: Gcj02Point): Promise<PlazaNameCandidate[]>;
}
