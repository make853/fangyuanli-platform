import type { Gcj02Point } from "./location-context.js";
import {
  PlazaNameSelector,
  type AmapNamingPayload
} from "./plaza-name-selector.js";
import {
  PlazaNamingProvider,
  type PlazaNameCandidate
} from "./plaza-naming.provider.js";

const AMAP_REVERSE_GEOCODE_URL = "https://restapi.amap.com/v3/geocode/regeo";
const AMAP_PLACE_AROUND_URL = "https://restapi.amap.com/v5/place/around";
const REGIONAL_LANDMARK_KEYWORDS = [
  "广场",
  "公园",
  "体育场",
  "体育馆",
  "火车站",
  "高铁站",
  "地铁站",
  "客运站",
  "购物中心",
  "商场",
  "博物馆",
  "图书馆",
  "文化中心",
  "医院",
  "大学"
].join("|");

type AmapReverseResponse = {
  status?: unknown;
  info?: unknown;
  regeocode?: unknown;
};

type AmapAroundResponse = {
  status?: unknown;
  info?: unknown;
  pois?: unknown;
};

export type AmapPlazaNamingOptions = {
  environment?: NodeJS.ProcessEnv;
  fetcher?: typeof fetch;
};

export class AmapPlazaNamingProvider extends PlazaNamingProvider {
  private readonly environment: NodeJS.ProcessEnv;
  private readonly fetcher: typeof fetch;

  constructor(
    private readonly selector: PlazaNameSelector,
    options: AmapPlazaNamingOptions = {}
  ) {
    super();
    this.environment = options.environment ?? process.env;
    this.fetcher = options.fetcher ?? fetch;
  }

  isConfigured(): boolean {
    return Boolean(this.environment.AMAP_WEB_SERVICE_KEY?.trim());
  }

  async candidates(point: Gcj02Point): Promise<PlazaNameCandidate[]> {
    const key = this.environment.AMAP_WEB_SERVICE_KEY?.trim();
    if (!key) return [];

    const reverseUrl = this.reverseUrl(key, point);
    const aroundUrl = this.aroundUrl(key, point);
    const [reverse, around] = await Promise.allSettled([
      this.reverseGeocode(reverseUrl),
      this.regionalLandmarks(aroundUrl)
    ]);
    if (reverse.status === "rejected" && around.status === "rejected") {
      throw new Error("Amap plaza naming sources are unavailable");
    }

    const payload: AmapNamingPayload =
      reverse.status === "fulfilled" ? reverse.value : {};
    if (around.status === "fulfilled") payload.regionalPois = around.value;
    return this.selector.select(payload);
  }

  private reverseUrl(key: string, point: Gcj02Point): URL {
    const url = new URL(AMAP_REVERSE_GEOCODE_URL);
    this.locationParams(url, key, point);
    // 1600m covers the half diagonal of the active 2km grid while avoiding
    // unrelated POI noise farther away.
    url.searchParams.set("radius", "1600");
    url.searchParams.set("extensions", "all");
    url.searchParams.set("roadlevel", "1");
    url.searchParams.set("output", "JSON");
    return url;
  }

  private aroundUrl(key: string, point: Gcj02Point): URL {
    const url = new URL(AMAP_PLACE_AROUND_URL);
    this.locationParams(url, key, point);
    url.searchParams.set("radius", "3000");
    url.searchParams.set("keywords", REGIONAL_LANDMARK_KEYWORDS);
    url.searchParams.set("sortrule", "distance");
    url.searchParams.set("page_size", "25");
    url.searchParams.set("page_num", "1");
    url.searchParams.set("show_fields", "business");
    url.searchParams.set("output", "JSON");
    return url;
  }

  private locationParams(url: URL, key: string, point: Gcj02Point): void {
    url.searchParams.set("key", key);
    url.searchParams.set(
      "location",
      `${point.longitude.toFixed(6)},${point.latitude.toFixed(6)}`
    );
  }

  private async reverseGeocode(url: URL): Promise<AmapNamingPayload> {
    const response = await this.fetcher(url, {
      signal: AbortSignal.timeout(2_000)
    });
    if (!response.ok) {
      throw new Error(`Amap reverse geocoding is unavailable (${response.status})`);
    }
    const payload = (await response.json()) as AmapReverseResponse;
    if (payload.status !== "1" || !payload.regeocode || typeof payload.regeocode !== "object") {
      throw new Error(
        `Amap reverse geocoding failed (${this.safeInfo(payload.info)})`
      );
    }
    return payload.regeocode as AmapNamingPayload;
  }

  private async regionalLandmarks(url: URL): Promise<unknown> {
    const response = await this.fetcher(url, {
      signal: AbortSignal.timeout(2_000)
    });
    if (!response.ok) {
      throw new Error(`Amap place around is unavailable (${response.status})`);
    }
    const payload = (await response.json()) as AmapAroundResponse;
    if (payload.status !== "1" || !Array.isArray(payload.pois)) {
      throw new Error(`Amap place around failed (${this.safeInfo(payload.info)})`);
    }
    return payload.pois;
  }

  private safeInfo(value: unknown): string {
    return typeof value === "string" && /^[A-Z0-9_ -]{1,80}$/i.test(value)
      ? value
      : "invalid response";
  }
}
