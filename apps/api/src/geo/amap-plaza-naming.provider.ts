import type { Gcj02Point } from "./location-context.js";
import { PlazaNameSelector } from "./plaza-name-selector.js";
import {
  PlazaNamingProvider,
  type PlazaNameCandidate
} from "./plaza-naming.provider.js";

const AMAP_REVERSE_GEOCODE_URL = "https://restapi.amap.com/v3/geocode/regeo";

type AmapResponse = {
  status?: unknown;
  info?: unknown;
  regeocode?: unknown;
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

    const url = new URL(AMAP_REVERSE_GEOCODE_URL);
    url.searchParams.set("key", key);
    url.searchParams.set(
      "location",
      `${point.longitude.toFixed(6)},${point.latitude.toFixed(6)}`
    );
    url.searchParams.set("radius", "1200");
    url.searchParams.set("extensions", "all");
    url.searchParams.set("roadlevel", "1");
    url.searchParams.set("output", "JSON");

    const response = await this.fetcher(url, {
      signal: AbortSignal.timeout(2_000)
    });
    if (!response.ok) {
      throw new Error(`Amap reverse geocoding is unavailable (${response.status})`);
    }
    const payload = (await response.json()) as AmapResponse;
    if (payload.status !== "1" || !payload.regeocode || typeof payload.regeocode !== "object") {
      throw new Error(
        `Amap reverse geocoding failed (${this.safeInfo(payload.info)})`
      );
    }
    return this.selector.select(payload.regeocode);
  }

  private safeInfo(value: unknown): string {
    return typeof value === "string" && /^[A-Z0-9_ -]{1,80}$/i.test(value)
      ? value
      : "invalid response";
  }
}
