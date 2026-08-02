import { Injectable } from "@nestjs/common";
import type {
  PlazaNameCandidate,
  PlazaNamingSource
} from "./plaza-naming.provider.js";

export type AmapNamingPayload = {
  addressComponent?: unknown;
  pois?: unknown;
  aois?: unknown;
  regionalPois?: unknown;
};

type RawCandidate = {
  name: string;
  type: string;
  distance: number;
  area: number;
  origin:
    | "aoi"
    | "poi"
    | "regional"
    | "businessArea"
    | "neighborhood"
    | "building";
};

const COMMUNITY_KEYWORDS = ["小区", "花园", "家园", "公寓", "社区", "新城"] as const;
const COMMUNITY_TYPES = ["住宅区", "住宅小区", "社区中心"] as const;
const PUBLIC_CULTURE_KEYWORDS = [
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
  "景区"
] as const;
const MAJOR_TRANSIT_KEYWORDS = [
  "火车站",
  "高铁站",
  "地铁站",
  "客运站",
  "汽车站",
  "机场"
] as const;
const MAJOR_MALL_KEYWORDS = ["购物中心", "商场", "商业广场", "购物广场"] as const;
const HIGHER_EDUCATION_TYPES = ["高等院校", "大学"] as const;
const BASIC_EDUCATION_TYPES = ["中学", "小学"] as const;
const MAJOR_HOSPITAL_TYPES = ["综合医院", "专科医院", "中医院"] as const;
const STABLE_TYPES = [
  "风景名胜",
  "体育场馆",
  "火车站",
  "长途汽车站",
  "机场",
  "产业园区",
  "商务住宅;产业园区"
] as const;
const UNSTABLE_TYPES = [
  "餐饮服务",
  "生活服务",
  "汽车服务",
  "住宿服务",
  "公司企业",
  "便民商店",
  "超级市场",
  "便利店"
] as const;
const SUBORDINATE_KEYWORDS = [
  "停车场",
  "出入口",
  "入口",
  "出口",
  "号口",
  "售票处",
  "服务台",
  "音乐喷泉",
  "喷泉",
  "相亲角",
  "治安派出所",
  "公交站"
] as const;
const ORGANIZATION_KEYWORDS = [
  "支部委员会",
  "居民委员会",
  "村民委员会",
  "委员会",
  "党群服务中心",
  "社区服务中心",
  "办事处",
  "办公室",
  "管理所",
  "警务室",
  "派出所"
] as const;
const LOW_QUALITY_EDUCATION = [
  "幼儿园",
  "托儿所",
  "早教",
  "托育",
  "培训机构"
] as const;
const MINOR_HEALTH_TYPES = [
  "诊所",
  "卫生室",
  "卫生站",
  "药房",
  "医疗保健服务场所"
] as const;
const MERCHANT_NAME_KEYWORDS = [
  "银行",
  "酒店",
  "宾馆",
  "饭店",
  "餐厅",
  "烧烤",
  "夜市",
  "足浴",
  "KTV"
] as const;
const ROAD_SUFFIXES = ["路", "街", "大道", "巷", "胡同", "公路"] as const;

@Injectable()
export class PlazaNameSelector {
  select(payload: AmapNamingPayload): PlazaNameCandidate[] {
    const raw = [
      ...this.items(payload.aois).map((item) => this.raw(item, "aoi")),
      ...this.items(payload.pois).map((item) => this.raw(item, "poi")),
      ...this.items(payload.regionalPois).map((item) => this.raw(item, "regional")),
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
    if (this.shouldReject(candidate)) return null;

    const community =
      this.includes(candidate.name, COMMUNITY_KEYWORDS) ||
      this.includes(candidate.type, COMMUNITY_TYPES);
    const citySquare = candidate.type.includes("城市广场");
    const publicCulture = this.includes(candidate.name, PUBLIC_CULTURE_KEYWORDS);
    const majorTransit =
      this.includes(candidate.name, MAJOR_TRANSIT_KEYWORDS) ||
      this.includes(candidate.type, MAJOR_TRANSIT_KEYWORDS);
    const majorMall =
      candidate.type.includes("购物服务;商场") &&
      (this.includes(candidate.name, MAJOR_MALL_KEYWORDS) ||
        candidate.name.endsWith("广场"));
    const majorHospital =
      /医院|中医院/u.test(candidate.name) &&
      this.includes(candidate.type, MAJOR_HOSPITAL_TYPES);
    const university =
      /大学|学院/u.test(candidate.name) &&
      this.includes(candidate.type, HIGHER_EDUCATION_TYPES);
    const basicSchool = this.includes(candidate.type, BASIC_EDUCATION_TYPES);
    const stableType = this.includes(candidate.type, STABLE_TYPES);
    let score = 0;
    let source: PlazaNamingSource = "landmark";

    // A residential project containing “广场” is still a community. Type semantics
    // take precedence over keyword coincidence.
    if (community) {
      score = 360;
      source = "community";
    } else if (citySquare && !this.isMerchantMasqueradingAsSquare(candidate)) {
      score = candidate.origin === "aoi" ? 1650 : 1550;
      source = "venue";
    } else if (majorTransit) {
      score = candidate.origin === "aoi" ? 1460 : 1360;
      source = "venue";
    } else if (publicCulture) {
      score = candidate.origin === "aoi" ? 1420 : 1320;
      source = "venue";
    } else if (majorMall) {
      score = candidate.origin === "aoi" ? 1280 : 1220;
      source = "venue";
    } else if (majorHospital || university) {
      score = candidate.origin === "aoi" ? 1240 : 1160;
      source = "venue";
    } else if (candidate.origin === "businessArea") {
      score = 920;
    } else if (candidate.origin === "aoi" && candidate.area >= 20_000) {
      score = 860;
    } else if (stableType && candidate.origin !== "building") {
      score = 700;
    } else if (basicSchool) {
      // Schools are persistent but identify only one institution, so they are a
      // last-resort fallback below regional landmarks, business areas and AOIs.
      score = 300;
    } else if (candidate.origin === "building" && stableType) {
      score = 450;
    } else {
      return null;
    }

    score += Math.min(120, candidate.area / 1000);
    score -= Math.min(3000, candidate.distance) * 0.11;
    return {
      name: this.displayName(candidate.name),
      source,
      score
    };
  }

  private shouldReject(candidate: RawCandidate): boolean {
    const { name, type } = candidate;
    if (
      this.isSubordinate(name) ||
      this.isOrganization(name) ||
      this.isRoadName(name) ||
      this.includes(name, MERCHANT_NAME_KEYWORDS) ||
      this.includes(name, LOW_QUALITY_EDUCATION) ||
      this.includes(type, LOW_QUALITY_EDUCATION) ||
      (type.includes("培训机构") && /学院|学校/u.test(name)) ||
      this.includes(type, MINOR_HEALTH_TYPES) ||
      (type.includes("公交车站") && !/客运站|汽车站/u.test(name))
    ) {
      return true;
    }
    return this.includes(type, UNSTABLE_TYPES) && !type.includes("购物服务;商场");
  }

  private isMerchantMasqueradingAsSquare(candidate: RawCandidate): boolean {
    return (
      this.includes(candidate.name, MERCHANT_NAME_KEYWORDS) ||
      /(?:店|馆店|分店|营业厅)(?:\)|）)?$/u.test(candidate.name) ||
      (candidate.type.includes("购物服务") && !candidate.type.includes("购物服务;商场"))
    );
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
    const type = this.text(item.type) ?? "";
    const rawName = this.text(item.name);
    const name = rawName ? this.normalizeName(rawName, type) : null;
    if (!name || [...name].length < 2 || [...name].length > 48) return null;
    return {
      name,
      type,
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

  private isRoadName(name: string): boolean {
    return ROAD_SUFFIXES.some((suffix) => name.endsWith(suffix));
  }

  private isOrganization(name: string): boolean {
    return name.startsWith("中共") || this.includes(name, ORGANIZATION_KEYWORDS);
  }

  private normalizeName(name: string, type: string): string {
    if (type.includes("地铁站")) {
      const withoutExit = name.replace(
        /[-—·\s]*(?:(?:[A-Za-z]\d*|\d+|[一二三四五六七八九十]+)号?(?:出入口|口))$/u,
        ""
      );
      const withoutMarker = withoutExit
        .replace(/[（(]地铁站[）)]$/u, "")
        .replace(/地铁站$/u, "")
        .replace(/站$/u, "");
      return withoutMarker ? `${withoutMarker}地铁站` : name;
    }

    if (type.includes("医疗保健服务") || /医院|中医院/u.test(name)) {
      const parent = name
        .replace(
          /[-—·\s]*(?:门诊综合楼|门诊楼|门诊部|住院部|住院楼|病房楼|医技楼|急诊楼|综合楼)$/u,
          ""
        )
        .replace(/[（(](?:门诊部|住院部|门诊楼|住院楼|综合楼)[）)]$/u, "");
      if ([...parent].length >= 2) return parent;
    }

    return name;
  }

  private isSubordinate(name: string): boolean {
    return (
      /[-—]/u.test(name) ||
      this.includes(name, SUBORDINATE_KEYWORDS) ||
      /(?:亭|桥|瀑布|雕塑|观景台|景点|东门|西门|南门|北门|正门|侧门|大门|店)(?:\)|）)?$/u.test(
        name
      )
    );
  }
}
