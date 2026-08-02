import type { Gcj02Point, LocationSnapshot } from "../geo/location-context.js";

export const PLACE_CATEGORY_KEYS = [
  "food_retail",
  "community",
  "culture_entertainment",
  "nightlife",
  "sports_fitness",
  "parks_scenic",
  "education_public",
  "shopping_district",
  "transport_other"
] as const;

export const PLACE_HEAT_LEVELS = [
  "quiet",
  "neutral",
  "active",
  "veryActive",
  "hot"
] as const;

export type PlaceCategoryKey = (typeof PLACE_CATEGORY_KEYS)[number];
export type PlaceHeatLevel = (typeof PLACE_HEAT_LEVELS)[number];
export type PlaceSort = "recommended" | "distance" | "heat";

export type PlaceCandidate = Gcj02Point & {
  provider: "amap";
  providerPlaceId: string;
  name: string;
  address: string | null;
  rawCategoryCode: string | null;
  rawCategoryName: string | null;
  categoryKey: PlaceCategoryKey;
  sourceUpdatedAt: Date;
};

export type RawPlaceCandidate = Omit<PlaceCandidate, "categoryKey">;

export type PlaceProjection = {
  placeGroupId: string;
  conversationId: string;
  name: string;
  address: string | null;
  categoryKey: PlaceCategoryKey;
  categoryName: string;
  longitude: number;
  latitude: number;
  certificationStatus: "unverified" | "reviewPending" | "verified";
  heatLevel: PlaceHeatLevel;
  latestSequence: number;
  lastReadSequence: number;
  notificationMode: "normal" | "muted";
  role: "owner" | "admin" | "resident" | "member" | null;
  speakPolicy: "nearbyAndMembers" | "membersOnly" | "adminsOnly";
  visibilityRadiusMeters: number;
  version: number;
};

export type PlaceDiscoverQuery = {
  location: LocationSnapshot;
  categoryKeys: PlaceCategoryKey[];
  heatLevels: PlaceHeatLevel[];
  historyOnly: boolean;
  keyword: string | null;
  distanceMeters: number;
};

export type PlaceDiscoverOptions = PlaceDiscoverQuery & {
  userId: string;
  sort: PlaceSort;
  offset: number;
  limit: number;
};

export type PlaceCard = {
  placeGroupId: string;
  conversationId: string;
  name: string;
  category: { key: PlaceCategoryKey; name: string };
  distance: { meters: number; display: string };
  certificationStatus: "unverified" | "reviewPending" | "verified";
  heat: { level: PlaceHeatLevel; display: string };
  unread: {
    count: number;
    appearance: "none" | "red" | "gray";
    firstUnreadSequence: number | null;
  };
  allowedActions: string[];
  version: number;
};

export class PlaceDomainError extends Error {
  constructor(
    public readonly code: string,
    message: string,
    public readonly status: number
  ) {
    super(message);
  }
}
