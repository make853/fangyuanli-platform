import type { Gcj02Point } from "./location-context.js";

export type PlazaNamingSource =
  | "landmark"
  | "venue"
  | "road"
  | "community";

export type PlazaNameCandidate = {
  name: string;
  source: PlazaNamingSource;
  score: number;
};

/**
 * Persisted policy version. Increment only when existing automatic names should
 * be reconsidered; plaza identity and conversation identity never change.
 */
export const PLAZA_NAMING_POLICY_VERSION = 2;

/** External map boundary. Implementations must never expose provider IDs as names. */
export abstract class PlazaNamingProvider {
  abstract isConfigured(): boolean;
  abstract candidates(point: Gcj02Point): Promise<PlazaNameCandidate[]>;
}
