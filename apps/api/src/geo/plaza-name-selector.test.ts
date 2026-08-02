import assert from "node:assert/strict";
import test from "node:test";
import { PlazaNameSelector } from "./plaza-name-selector.js";

test("prioritizes stable venues and filters small merchants and roads", () => {
  const candidates = new PlazaNameSelector().select({
    aois: [
      {
        name: "滨江体育中心",
        type: "体育休闲服务;体育场馆",
        area: "85000",
        distance: "40"
      },
      {
        name: "晴川花园",
        type: "商务住宅;住宅区",
        area: "120000",
        distance: "0"
      }
    ],
    pois: [
      {
        name: "老王咖啡店",
        type: "餐饮服务;咖啡厅",
        distance: "10"
      },
      {
        name: "城市博物馆",
        type: "科教文化服务;博物馆",
        distance: "160"
      }
    ],
    addressComponent: {
      businessAreas: [{ name: "滨江商圈", location: "121.1,31.1" }],
      neighborhood: { name: "晴川花园", type: "住宅区" },
      streetNumber: { street: "庄周大道" }
    }
  });

  assert.equal(candidates[0]?.name, "滨江体育中心广场");
  assert.equal(candidates.some((candidate) => candidate.name.includes("咖啡")), false);
  assert.equal(candidates.some((candidate) => candidate.name.includes("庄周大道")), false);
  assert.ok(
    candidates.findIndex((candidate) => candidate.name === "晴川花园广场") >
      candidates.findIndex((candidate) => candidate.name === "滨江商圈广场")
  );
});

test("prefers a city plaza over its entrances, fountains and minor attractions", () => {
  const candidates = new PlazaNameSelector().select({
    aois: [
      {
        name: "上海市人民政府",
        type: "130102",
        area: "34587",
        distance: "0"
      }
    ],
    pois: [
      {
        name: "上海人民广场",
        type: "风景名胜;公园广场;城市广场",
        distance: "226"
      },
      {
        name: "上海人民广场音乐喷泉",
        type: "风景名胜;公园广场;城市广场",
        distance: "138"
      },
      {
        name: "人民广场地铁站1号口",
        type: "交通设施服务;地铁站;出入口",
        distance: "267"
      },
      {
        name: "人民公园-西山亭",
        type: "风景名胜;风景名胜相关;旅游景点",
        distance: "40"
      }
    ],
    addressComponent: {
      businessAreas: [
        { name: "淮海路" },
        { name: "人民广场商圈" }
      ]
    }
  });

  assert.equal(candidates[0]?.name, "上海人民广场");
  assert.equal(
    candidates.some((candidate) =>
      /音乐喷泉|号口|西山亭|淮海路/u.test(candidate.name)
    ),
    false
  );
  assert.equal(
    candidates.some((candidate) => candidate.name === "人民广场地铁站广场"),
    true
  );
  assert.equal(
    candidates.some((candidate) => candidate.name === "人民广场商圈广场"),
    true
  );
});

test("collapses metro exits into one stable station candidate", () => {
  const candidates = new PlazaNameSelector().select({
    pois: [
      {
        name: "民权站地铁站1号口",
        type: "交通设施服务;地铁站;出入口",
        distance: "80"
      },
      {
        name: "民权站A口",
        type: "交通设施服务;地铁站;出入口",
        distance: "120"
      },
      {
        name: "民权站(地铁站)",
        type: "交通设施服务;地铁站",
        distance: "100"
      }
    ]
  });

  assert.deepEqual(
    candidates.map((candidate) => candidate.name),
    ["民权地铁站广场"]
  );
});

test("filters local organizations and keeps community names low priority", () => {
  const candidates = new PlazaNameSelector().select({
    pois: [
      {
        name: "中共贸易西路社区支部委员会",
        type: "政府机构及社会团体;政府机关",
        distance: "20"
      },
      {
        name: "贸易西路居民委员会",
        type: "政府机构及社会团体;政府机关",
        distance: "30"
      },
      {
        name: "贸易西路社区",
        type: "政府机构及社会团体;政府机关",
        distance: "40"
      }
    ]
  });

  assert.deepEqual(candidates, [
    {
      name: "贸易西路社区广场",
      source: "community",
      score: 264
    }
  ]);
});
