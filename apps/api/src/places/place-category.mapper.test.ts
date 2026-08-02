import assert from "node:assert/strict";
import test from "node:test";
import { PlaceCategoryMapper } from "./place-category.mapper.js";

const mapper = new PlaceCategoryMapper();

test("maps community before generic public-service keywords", () => {
  assert.equal(
    mapper.map({
      name: "晴川花园小区",
      rawCategoryCode: "120302",
      rawCategoryName: "住宅小区"
    }),
    "community"
  );
});

test("maps representative commercial, nightlife and sports places", () => {
  assert.equal(
    mapper.map({
      name: "隆江猪脚饭",
      rawCategoryCode: "050100",
      rawCategoryName: "中餐厅"
    }),
    "food_retail"
  );
  assert.equal(
    mapper.map({
      name: "夜航酒吧",
      rawCategoryCode: null,
      rawCategoryName: "酒吧"
    }),
    "nightlife"
  );
  assert.equal(
    mapper.map({
      name: "滨河健身广场",
      rawCategoryCode: null,
      rawCategoryName: "公共健身场地"
    }),
    "sports_fitness"
  );
});

test("keeps unknown map types in a safe catch-all category", () => {
  assert.equal(
    mapper.map({
      name: "未分类地点",
      rawCategoryCode: "999999",
      rawCategoryName: null
    }),
    "transport_other"
  );
});
