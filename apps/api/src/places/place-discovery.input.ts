import { Injectable } from "@nestjs/common";
import type { LocationSnapshot } from "../geo/location-context.js";
import {
  PLACE_CATEGORY_KEYS,
  PLACE_HEAT_LEVELS,
  PlaceDomainError,
  type PlaceCategoryKey,
  type PlaceDiscoverOptions,
  type PlaceHeatLevel,
  type PlaceSort
} from "./place.types.js";

const CATEGORY_KEYS = new Set<string>(PLACE_CATEGORY_KEYS);
const HEAT_LEVELS = new Set<string>(PLACE_HEAT_LEVELS);
const SORTS = new Set<PlaceSort>(["recommended", "distance", "heat"]);

@Injectable()
export class PlaceDiscoveryInput {
  parse(input: {
    userId: string;
    location: LocationSnapshot;
    body: Record<string, unknown>;
  }): PlaceDiscoverOptions {
    const filters = this.record(input.body.filters, "PLACE_FILTERS_INVALID");
    const distance = filters.distanceMeters ?? 5000;
    if (
      typeof distance !== "number" ||
      !Number.isInteger(distance) ||
      distance < 100 ||
      distance > 30_000
    ) {
      throw new PlaceDomainError(
        "PLACE_DISTANCE_INVALID",
        "地点范围应为100米至30公里",
        422
      );
    }
    const limit = input.body.limit ?? 20;
    if (
      typeof limit !== "number" ||
      !Number.isInteger(limit) ||
      limit < 1 ||
      limit > 50
    ) {
      throw new PlaceDomainError("PLACE_LIMIT_INVALID", "每页数量无效", 400);
    }
    const sort = input.body.sort ?? "recommended";
    if (typeof sort !== "string" || !SORTS.has(sort as PlaceSort)) {
      throw new PlaceDomainError("PLACE_SORT_INVALID", "地点排序方式无效", 400);
    }
    const keyword = filters.keyword;
    if (
      keyword !== undefined &&
      keyword !== null &&
      (typeof keyword !== "string" || keyword.trim().length > 80)
    ) {
      throw new PlaceDomainError("PLACE_KEYWORD_INVALID", "地点关键词无效", 400);
    }
    if (filters.historyOnly !== undefined && typeof filters.historyOnly !== "boolean") {
      throw new PlaceDomainError("PLACE_HISTORY_FILTER_INVALID", "历史筛选无效", 400);
    }
    return {
      userId: input.userId,
      location: input.location,
      categoryKeys: this.stringArray<PlaceCategoryKey>(
        filters.categoryKeys,
        CATEGORY_KEYS,
        "PLACE_CATEGORY_INVALID"
      ),
      heatLevels: this.stringArray<PlaceHeatLevel>(
        filters.heatLevels,
        HEAT_LEVELS,
        "PLACE_HEAT_INVALID"
      ),
      historyOnly: filters.historyOnly === true,
      keyword: typeof keyword === "string" && keyword.trim() ? keyword.trim() : null,
      distanceMeters: distance,
      sort: sort as PlaceSort,
      offset: this.decodeCursor(input.body.cursor),
      limit
    };
  }

  encodeCursor(offset: number): string {
    return Buffer.from(JSON.stringify({ version: 1, offset }), "utf8").toString(
      "base64url"
    );
  }

  private record(value: unknown, code: string): Record<string, unknown> {
    if (value === undefined) return {};
    if (!value || typeof value !== "object" || Array.isArray(value)) {
      throw new PlaceDomainError(code, "地点筛选格式无效", 400);
    }
    return value as Record<string, unknown>;
  }

  private stringArray<T extends string>(
    value: unknown,
    allowed: Set<string>,
    code: string
  ): T[] {
    if (value === undefined) return [];
    if (
      !Array.isArray(value) ||
      value.some((item) => typeof item !== "string" || !allowed.has(item))
    ) {
      throw new PlaceDomainError(code, "地点筛选选项无效", 400);
    }
    return [...new Set(value)] as T[];
  }

  private decodeCursor(value: unknown): number {
    if (value === undefined || value === null) return 0;
    if (typeof value !== "string" || !value) {
      throw new PlaceDomainError("PLACE_CURSOR_INVALID", "分页位置无效", 400);
    }
    try {
      const decoded = JSON.parse(Buffer.from(value, "base64url").toString("utf8")) as {
        version?: unknown;
        offset?: unknown;
      };
      if (
        decoded.version !== 1 ||
        typeof decoded.offset !== "number" ||
        !Number.isInteger(decoded.offset) ||
        decoded.offset < 0 ||
        decoded.offset > 10_000
      ) {
        throw new Error("invalid cursor");
      }
      return decoded.offset;
    } catch {
      throw new PlaceDomainError("PLACE_CURSOR_INVALID", "分页位置已失效", 400);
    }
  }
}
