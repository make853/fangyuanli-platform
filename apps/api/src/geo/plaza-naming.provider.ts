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

/** External map boundary. Implementations must never expose provider IDs as names. */
export abstract class PlazaNamingProvider {
  abstract isConfigured(): boolean;
  abstract candidates(point: Gcj02Point): Promise<PlazaNameCandidate[]>;
}
