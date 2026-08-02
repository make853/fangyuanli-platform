import { Injectable } from "@nestjs/common";
import type { LocationSnapshot } from "../geo/location-context.js";
import type { PlaceCategoryKey, RawPlaceCandidate } from "./place.types.js";

export type PlaceCandidateRequest = {
  location: LocationSnapshot;
  radiusMeters: number;
  keyword: string | null;
  categoryKeys: PlaceCategoryKey[];
  limit: number;
};

/** External map boundary. Amap is plugged in here after credential and GCJ-02 QA. */
@Injectable()
export class PlaceCandidateProvider {
  discover(_request: PlaceCandidateRequest): Promise<RawPlaceCandidate[]> {
    return Promise.resolve([]);
  }
}
