import { Inject, Injectable, Optional } from "@nestjs/common";
import type { LocationSnapshot } from "../geo/location-context.js";
import type { PlaceCategoryKey, RawPlaceCandidate } from "./place.types.js";

const AMAP_PLACE_AROUND_URL = "https://restapi.amap.com/v5/place/around";
const MAX_AMAP_PAGE_SIZE = 25;
const MAX_CACHE_ENTRIES = 512;
const CACHE_TTL_MS = 2 * 60 * 1000;
const FAILURE_CACHE_TTL_MS = 15 * 1000;
const PLACE_CANDIDATE_PROVIDER_OPTIONS = Symbol(
  "PLACE_CANDIDATE_PROVIDER_OPTIONS"
);

const AMAP_TYPES_BY_CATEGORY: Record<PlaceCategoryKey, readonly string[]> = {
  food_retail: ["050000", "060000", "070000"],
  community: ["120300"],
  culture_entertainment: ["080200", "140400"],
  nightlife: ["080300"],
  sports_fitness: ["080100"],
  parks_scenic: ["110000"],
  education_public: ["130000", "140000", "170000"],
  shopping_district: ["060100"],
  transport_other: ["100000", "150000", "160000"]
};

const DEFAULT_AMAP_TYPES = [
  "050000",
  "060000",
  "070000",
  "080000",
  "100000",
  "110000",
  "120300",
  "130000",
  "140000",
  "150000",
  "160000",
  "170000"
] as const;

type AmapPlaceResponse = {
  status?: unknown;
  info?: unknown;
  pois?: unknown;
};

type AmapPoi = {
  id?: unknown;
  name?: unknown;
  address?: unknown;
  location?: unknown;
  type?: unknown;
  typecode?: unknown;
};

export type PlaceCandidateProviderOptions = {
  environment?: NodeJS.ProcessEnv;
  fetcher?: typeof fetch;
  now?: () => Date;
};

export class PlaceCandidateProviderError extends Error {}

export type PlaceCandidateRequest = {
  location: LocationSnapshot;
  radiusMeters: number;
  keyword: string | null;
  categoryKeys: PlaceCategoryKey[];
  limit: number;
};

@Injectable()
export class PlaceCandidateProvider {
  private readonly environment: NodeJS.ProcessEnv;
  private readonly fetcher: typeof fetch;
  private readonly now: () => Date;
  private readonly cache = new Map<
    string,
    { expiresAt: number; promise: Promise<RawPlaceCandidate[]> }
  >();

  constructor(
    @Optional()
    @Inject(PLACE_CANDIDATE_PROVIDER_OPTIONS)
    options: PlaceCandidateProviderOptions = {}
  ) {
    this.environment = options.environment ?? process.env;
    this.fetcher = options.fetcher ?? fetch;
    this.now = options.now ?? (() => new Date());
  }

  isConfigured(): boolean {
    return Boolean(this.environment.AMAP_WEB_SERVICE_KEY?.trim());
  }

  discover(request: PlaceCandidateRequest): Promise<RawPlaceCandidate[]> {
    const key = this.environment.AMAP_WEB_SERVICE_KEY?.trim();
    if (!key) return Promise.resolve([]);

    const cacheKey = this.cacheKey(request);
    const now = this.now().getTime();
    const cached = this.cache.get(cacheKey);
    if (cached && cached.expiresAt > now) return cached.promise;
    if (cached) this.cache.delete(cacheKey);

    const promise = this.fetchCandidates(key, request).catch((error: unknown) => {
      const current = this.cache.get(cacheKey);
      if (current?.promise === promise) {
        current.expiresAt = this.now().getTime() + FAILURE_CACHE_TTL_MS;
      }
      if (error instanceof PlaceCandidateProviderError) throw error;
      throw new PlaceCandidateProviderError(
        "Amap place discovery is unavailable",
        { cause: error }
      );
    });
    this.pruneCache(now);
    this.cache.set(cacheKey, { expiresAt: now + CACHE_TTL_MS, promise });
    return promise;
  }

  private async fetchCandidates(
    key: string,
    request: PlaceCandidateRequest
  ): Promise<RawPlaceCandidate[]> {
    const requestedLimit = Math.max(1, Math.min(50, request.limit));
    const pageCount = Math.ceil(requestedLimit / MAX_AMAP_PAGE_SIZE);
    const responses = await Promise.all(
      Array.from({ length: pageCount }, (_, index) =>
        this.fetchPage(this.requestUrl(key, request, index + 1, requestedLimit))
      )
    );
    const candidates = responses
      .flatMap((response) => response)
      .map((poi) => this.parsePoi(poi))
      .filter((candidate): candidate is RawPlaceCandidate => candidate !== null);
    return [
      ...new Map(
        candidates.map((candidate) => [candidate.providerPlaceId, candidate])
      ).values()
    ].slice(0, requestedLimit);
  }

  private requestUrl(
    key: string,
    request: PlaceCandidateRequest,
    page: number,
    requestedLimit: number
  ): URL {
    const url = new URL(AMAP_PLACE_AROUND_URL);
    url.searchParams.set("key", key);
    url.searchParams.set(
      "location",
      `${request.location.longitude.toFixed(6)},${request.location.latitude.toFixed(6)}`
    );
    url.searchParams.set("radius", String(Math.min(50_000, request.radiusMeters)));
    url.searchParams.set("types", this.amapTypes(request.categoryKeys).join("|"));
    if (request.keyword) url.searchParams.set("keywords", request.keyword);
    url.searchParams.set("sortrule", request.keyword ? "weight" : "distance");
    url.searchParams.set(
      "page_size",
      String(Math.min(MAX_AMAP_PAGE_SIZE, requestedLimit))
    );
    url.searchParams.set("page_num", String(page));
    url.searchParams.set("output", "JSON");
    return url;
  }

  private async fetchPage(url: URL): Promise<AmapPoi[]> {
    const response = await this.fetcher(url, {
      signal: AbortSignal.timeout(2_000)
    });
    if (!response.ok) {
      throw new PlaceCandidateProviderError(
        `Amap place discovery is unavailable (${response.status})`
      );
    }
    const payload = (await response.json()) as AmapPlaceResponse;
    if (payload.status !== "1" || !Array.isArray(payload.pois)) {
      throw new PlaceCandidateProviderError(
        `Amap place discovery failed (${this.safeInfo(payload.info)})`
      );
    }
    return payload.pois as AmapPoi[];
  }

  private parsePoi(poi: AmapPoi): RawPlaceCandidate | null {
    const providerPlaceId = this.text(poi.id);
    const name = this.text(poi.name);
    const point = this.point(poi.location);
    if (!providerPlaceId || !name || !point) return null;
    return {
      provider: "amap",
      providerPlaceId,
      name,
      address: this.text(poi.address),
      coordinateSystem: "gcj02",
      ...point,
      rawCategoryCode: this.text(poi.typecode),
      rawCategoryName: this.text(poi.type),
      sourceUpdatedAt: this.now()
    };
  }

  private point(value: unknown): { longitude: number; latitude: number } | null {
    if (typeof value !== "string") return null;
    const [longitudeText, latitudeText, extra] = value.split(",");
    if (extra !== undefined) return null;
    const longitude = Number(longitudeText);
    const latitude = Number(latitudeText);
    if (
      !Number.isFinite(longitude) ||
      !Number.isFinite(latitude) ||
      longitude < -180 ||
      longitude > 180 ||
      latitude < -90 ||
      latitude > 90
    ) {
      return null;
    }
    return { longitude, latitude };
  }

  private amapTypes(categoryKeys: PlaceCategoryKey[]): string[] {
    const selected =
      categoryKeys.length === 0
        ? DEFAULT_AMAP_TYPES
        : categoryKeys.flatMap((categoryKey) => AMAP_TYPES_BY_CATEGORY[categoryKey]);
    return [...new Set(selected)];
  }

  private cacheKey(request: PlaceCandidateRequest): string {
    return JSON.stringify({
      longitude: request.location.longitude.toFixed(3),
      latitude: request.location.latitude.toFixed(3),
      radiusMeters: request.radiusMeters,
      keyword: request.keyword?.trim().toLowerCase() ?? null,
      categoryKeys: [...request.categoryKeys].sort(),
      limit: request.limit
    });
  }

  private pruneCache(now: number): void {
    for (const [key, entry] of this.cache) {
      if (entry.expiresAt <= now) this.cache.delete(key);
    }
    while (this.cache.size >= MAX_CACHE_ENTRIES) {
      const oldestKey = this.cache.keys().next().value as string | undefined;
      if (!oldestKey) return;
      this.cache.delete(oldestKey);
    }
  }

  private text(value: unknown): string | null {
    return typeof value === "string" && value.trim() ? value.trim() : null;
  }

  private safeInfo(value: unknown): string {
    return typeof value === "string" && /^[A-Z0-9_ -]{1,80}$/i.test(value)
      ? value
      : "invalid response";
  }
}
