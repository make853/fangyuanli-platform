import { Injectable } from "@nestjs/common";
import type { PlaceCategoryKey } from "./place.types.js";

type Rule = {
  categoryKey: PlaceCategoryKey;
  codePrefixes: readonly string[];
  keywords: readonly string[];
};

const RULES: readonly Rule[] = [
  {
    categoryKey: "community",
    codePrefixes: ["1203"],
    keywords: ["小区", "花园", "家园", "公寓", "社区"]
  },
  {
    categoryKey: "nightlife",
    codePrefixes: ["0803"],
    keywords: ["酒吧", "夜店", "清吧", "livehouse"]
  },
  {
    categoryKey: "sports_fitness",
    codePrefixes: ["0801"],
    keywords: ["健身", "体育", "球馆", "球场", "游泳", "瑜伽"]
  },
  {
    categoryKey: "parks_scenic",
    codePrefixes: ["1101", "1102"],
    keywords: ["公园", "景区", "湿地", "植物园", "动物园"]
  },
  {
    categoryKey: "culture_entertainment",
    codePrefixes: ["0802", "1404"],
    keywords: ["影院", "影城", "剧院", "音乐厅", "演出", "博物馆", "KTV"]
  },
  {
    categoryKey: "shopping_district",
    codePrefixes: ["0601"],
    keywords: ["商场", "购物中心", "商业街", "步行街"]
  },
  {
    categoryKey: "food_retail",
    codePrefixes: ["05", "06"],
    keywords: ["餐厅", "饭店", "咖啡", "便利店", "超市", "零售"]
  },
  {
    categoryKey: "education_public",
    codePrefixes: ["14", "13", "1701"],
    keywords: ["学校", "大学", "医院", "政务", "服务中心", "图书馆"]
  }
];

@Injectable()
export class PlaceCategoryMapper {
  map(input: {
    name: string;
    rawCategoryCode: string | null;
    rawCategoryName: string | null;
  }): PlaceCategoryKey {
    const code = input.rawCategoryCode?.trim() ?? "";
    const searchable = `${input.name} ${input.rawCategoryName ?? ""}`.toLowerCase();
    for (const rule of RULES) {
      if (
        rule.codePrefixes.some((prefix) => code.startsWith(prefix)) ||
        rule.keywords.some((keyword) => searchable.includes(keyword.toLowerCase()))
      ) {
        return rule.categoryKey;
      }
    }
    return "transport_other";
  }
}
