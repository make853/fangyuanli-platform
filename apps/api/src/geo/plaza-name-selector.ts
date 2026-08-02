import { Injectable } from "@nestjs/common";
import type {
  PlazaNameCandidate,
  PlazaNamingSource
} from "./plaza-naming.provider.js";

export type AmapNamingPayload = {
  addressComponent?: unknown;
  pois?: unknown;
  aois?: unknown;
};

type RawCandidate = {
  name: string;
  type: string;
  distance: number;
  area: number;
  origin: "aoi" | "poi" | "businessArea" | "neighborhood" | "building";
};

const VENUE_KEYWORDS = [
  "体育场",
  "体育馆",
  "体育中心",
  "奥体中心",
  "会展中心",
  "展览中心",
  "博物馆",
  "图书馆",
  "文化中心",
  "艺术中心",
  "音乐厅",
  "剧院",
  "公园",
  "景区",
  "广场",
  "大学",
  "学院",
  "火车站",
  "高铁站",
  "客运站",
  "机场",
  "购物中心",
  "商场",
  "医院"
] as const;

const STABLE_TYPES = [
  "风景名胜",
  "科教文化服务",
  "体育休闲服务",
  "交通设施服务",
  "政府机构",
  "医疗保健服务",
  "产业园区",
  "商务住宅;产业园区"
] as const;

const COMMUNITY_KEYWORDS = ["小区", "花园", "家园", "公寓", "社区"] as const;
const UNSTABLE_TYPES = [
  "餐饮服务",
  "生活服务",
  "汽车服务",
  "住宿服务",
  "公司企业",
  "便民商店"
] as const;

@Injectable()
export class PlazaNameSelector {
  select(payload: AmapNamingPayload): PlazaNameCandidate[] {
    const raw = [
      ...this.items(payload.aois).map((item) => this.raw(item, "aoi")),
      ...this.items(payload.pois).map((item) => this.raw(item, "poi")),
      ...this.addressItems(payload.addressComponent, "businessAreas").map(
        (item) => this.raw(item, "businessArea")
      ),
      ...this.addressItems(payload.addressComponent, "neighborhood").map(
        (item) => this.raw(item, "neighborhood")
      ),
      ...this.addressItems(payload.addressComponent, "building").map((item) =>
        this.raw(item, "building")
      )
    ].filter((candidate): candidate is RawCandidate => candidate !== null);

    const byName = new Map<string, PlazaNameCandidate>();
    for (const candidate of raw) {
      const ranked = this.rank(candidate);
      if (!ranked) continue;
      const current = byName.get(ranked.name);
      if (!current || ranked.score > current.score) byName.set(ranked.name, ranked);
    }
    return [...byName.values()].sort(
      (left, right) => right.score - left.score || left.name.localeCompare(right.name, "zh-CN")
    );
  }

  private rank(candidate: RawCandidate): PlazaNameCandidate | null {
    const venue = this.includes(candidate.name, VENUE_KEYWORDS);
    const community = this.includes(candidate.name, COMMUNITY_KEYWORDS);
    const stableType = this.includes(candidate.type, STABLE_TYPES);
    const unstableType = this.includes(candidate.type, UNSTABLE_TYPES);
    let score = 0;
    let source: PlazaNamingSource = "landmark";

    if (candidate.origin === "businessArea") {
      score = 850;
    } else if (venue && !unstableType) {
      score = candidate.origin === "aoi" ? 1200 : 1080;
      source = "venue";
    } else if (
      candidate.origin === "aoi" &&
      !community &&
      (candidate.area >= 20_000 || stableType)
    ) {
      score = 930;
    } else if (candidate.origin === "poi" && stableType && !unstableType) {
      score = 760;
    } else if (community) {
      score = 280;
      source = "community";
    } else if (candidate.origin === "building" && stableType) {
      score = 520;
    } else {
      return null;
    }

    score += Math.min(100, candidate.area / 1000);
    score -= Math.min(500, candidate.distance) * 0.4;
    return {
      name: this.displayName(candidate.name),
      source,
      score
    };
  }

  private displayName(value: string): string {
    const characters = [...value.trim()];
    const name = characters.slice(0, 40).join("");
    return name.endsWith("广场") ? name : `${name}广场`;
  }

  private raw(
    item: Record<string, unknown>,
    origin: RawCandidate["origin"]
  ): RawCandidate | null {
    const name = this.text(item.name);
    if (!name || [...name].length < 2 || [...name].length > 48) return null;
    return {
      name,
      type: this.text(item.type) ?? "",
      distance: this.number(item.distance),
      area: this.number(item.area),
      origin
    };
  }

  private addressItems(value: unknown, key: string): Record<string, unknown>[] {
    if (!value || typeof value !== "object" || Array.isArray(value)) return [];
    return this.items((value as Record<string, unknown>)[key]);
  }

  private items(value: unknown): Record<string, unknown>[] {
    if (Array.isArray(value)) {
      return value.filter(
        (item): item is Record<string, unknown> =>
          item !== null && typeof item === "object" && !Array.isArray(item)
      );
    }
    if (value !== null && typeof value === "object") {
      return [value as Record<string, unknown>];
    }
    return [];
  }

  private text(value: unknown): string | null {
    return typeof value === "string" && value.trim() ? value.trim() : null;
  }

  private number(value: unknown): number {
    const parsed = Number(value);
    return Number.isFinite(parsed) && parsed >= 0 ? parsed : 0;
  }

  private includes(value: string, keywords: readonly string[]): boolean {
    const normalized = value.toLowerCase();
    return keywords.some((keyword) => normalized.includes(keyword.toLowerCase()));
  }
}
