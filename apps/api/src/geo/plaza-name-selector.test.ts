import assert from "node:assert/strict";
import test from "node:test";
import { PlazaNameSelector } from "./plaza-name-selector.js";

test("prioritizes stable venues and excludes communities and small merchants", () => {
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
  assert.equal(candidates.some((candidate) => candidate.name.includes("晴川花园")), false);
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

test("keeps representative metro stations but excludes hospital and college station names", () => {
  const candidates = new PlazaNameSelector().select({
    pois: [
      {
        name: "市人民医院(地铁站)",
        type: "交通设施服务;地铁站",
        distance: "100"
      },
      {
        name: "实验中学站(地铁站)",
        type: "交通设施服务;地铁站",
        distance: "100"
      },
      {
        name: "城市学院站(地铁站)",
        type: "交通设施服务;地铁站",
        distance: "100"
      },
      {
        name: "城市中心广场",
        type: "风景名胜;公园广场;城市广场",
        distance: "100"
      }
    ]
  });

  const byName = new Map(candidates.map((candidate) => [candidate.name, candidate]));
  assert.equal(byName.get("实验中学地铁站广场")?.kind, "transit");
  assert.equal(byName.has("市人民医院地铁站广场"), false);
  assert.equal(byName.has("城市学院地铁站广场"), false);
  assert.equal(
    byName.get("实验中学地铁站广场")?.score,
    byName.get("城市中心广场")?.score
  );
});

test("filters local organizations and community names", () => {
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

  assert.deepEqual(candidates, []);
});

test("prefers regional landmarks and rejects low-quality school, office and training names", () => {
  const candidates = new PlazaNameSelector().select({
    aois: [
      {
        name: "乐鼎·明德府",
        type: "商务住宅;住宅区",
        area: "75582",
        distance: "200"
      }
    ],
    pois: [
      {
        name: "庄周双语小学",
        type: "科教文化服务;学校;小学",
        distance: "80"
      },
      {
        name: "民权县欢欢幼儿园",
        type: "科教文化服务;学校;幼儿园",
        distance: "60"
      },
      {
        name: "成品流流通办公室",
        type: "政府机构及社会团体;政府机关",
        distance: "50"
      },
      {
        name: "雅芝林商学院",
        type: "科教文化服务;培训机构;培训机构",
        distance: "40"
      }
    ],
    regionalPois: [
      {
        name: "民生广场",
        type: "风景名胜;公园广场;城市广场",
        distance: "900"
      },
      {
        name: "民权站广场",
        type: "风景名胜;公园广场;城市广场",
        distance: "1100"
      },
      {
        name: "圣晖广场",
        type: "购物服务;商场;购物中心",
        distance: "700"
      },
      {
        name: "建设银行中央城市广场",
        type: "风景名胜;公园广场;城市广场",
        distance: "300"
      }
    ]
  });

  assert.deepEqual(candidates.slice(0, 3).map((candidate) => candidate.name), [
    "民生广场",
    "民权站广场",
    "圣晖广场"
  ]);
  assert.equal(
    candidates.some((candidate) =>
      /幼儿园|办公室|商学院|建设银行/u.test(candidate.name)
    ),
    false
  );
  assert.equal(
    candidates.some((candidate) => /庄周双语小学|乐鼎·明德府/u.test(candidate.name)),
    false
  );
});

test("excludes hospitals and their subordinate buildings", () => {
  const candidates = new PlazaNameSelector().select({
    pois: [
      {
        name: "民权中医院门诊综合楼",
        type: "医疗保健服务;综合医院",
        distance: "90"
      },
      {
        name: "民权中医院-门诊部",
        type: "医疗保健服务;综合医院",
        distance: "120"
      }
    ]
  });

  assert.deepEqual(candidates, []);
});

test("keeps representative public, heritage and commercial choices but excludes communities", () => {
  const candidates = new PlazaNameSelector().select({
    regionalPois: [
      {
        name: "中央城市广场",
        type: "购物服务;商场;购物中心",
        distance: "1200"
      },
      {
        name: "圣晖广场",
        type: "购物服务;商场;购物中心",
        distance: "900"
      },
      {
        name: "民权站",
        type: "交通设施服务;火车站",
        distance: "1100"
      },
      {
        name: "民权县葡萄酒厂遗址",
        type: "风景名胜;风景名胜相关;旅游景点",
        distance: "1400"
      },
      {
        name: "华联城广场",
        type: "购物服务;商场;购物中心",
        distance: "1600"
      }
    ],
    aois: [
      {
        name: "南华社区",
        type: "商务住宅;住宅区",
        area: "90000",
        distance: "200"
      },
      {
        name: "绿洲社区",
        type: "商务住宅;住宅区",
        area: "70000",
        distance: "500"
      }
    ]
  });

  const byName = new Map(candidates.map((candidate) => [candidate.name, candidate]));
  assert.equal(byName.get("民权站广场")?.kind, "transit");
  assert.equal(byName.get("民权县葡萄酒厂遗址广场")?.kind, "culture_scenic");
  assert.equal(byName.get("中央城市广场")?.kind, "commercial_landmark");
  assert.equal(byName.get("圣晖广场")?.kind, "commercial_landmark");
  assert.equal(byName.get("华联城广场")?.kind, "commercial_landmark");
  assert.equal(byName.has("南华社区广场"), false);
  assert.equal(byName.has("绿洲社区广场"), false);
});

test("keeps station and scenic semantics when AMap also types them as city plazas", () => {
  const candidates = new PlazaNameSelector().select({
    pois: [
      { name: "民权北站站前广场", type: "风景名胜;公园广场;城市广场", distance: "500" },
      { name: "葡萄酒厂遗址广场", type: "风景名胜;公园广场;城市广场", distance: "600" },
      { name: "民生广场", type: "风景名胜;公园广场;城市广场", distance: "700" }
    ]
  });

  assert.equal(candidates.find((item) => item.name === "民权北站站前广场")?.kind, "transit");
  assert.equal(candidates.find((item) => item.name === "葡萄酒厂遗址广场")?.kind, "culture_scenic");
  assert.equal(candidates.find((item) => item.name === "民生广场")?.kind, "public_square");
});

test("uses road intersections and plain roads before villages", () => {
  const candidates = new PlazaNameSelector().select({
    aois: [
      {
        name: "赵庄村",
        type: "地名地址信息;普通地名;村庄级地名",
        area: "50000",
        distance: "300"
      },
      {
        name: "鲁庄新村",
        type: "地名地址信息;普通地名;村庄级地名",
        area: "42000",
        distance: "400"
      }
    ],
    roadinters: [
      {
        first_name: "西郊北路",
        second_name: "庄周大道",
        distance: "100"
      }
    ],
    roads: [{ name: "西郊北路", distance: "60" }]
  });

  assert.deepEqual(
    candidates.map((candidate) => candidate.name),
    ["西郊北路·庄周大道广场", "西郊北路广场", "赵庄广场", "鲁庄新村广场"]
  );
  assert.equal(candidates[0]?.kind, "road");
  assert.equal(candidates[2]?.kind, "village");
});

test("keeps the confirmed semantic priority independent of distance", () => {
  const candidates = new PlazaNameSelector().select({
    pois: [
      { name: "中心地铁站", type: "交通设施服务;地铁站", distance: "3000" },
      { name: "民生广场", type: "风景名胜;公园广场;城市广场", distance: "2900" },
      { name: "民权火车站", type: "交通设施服务;火车站", distance: "2500" },
      { name: "葡萄酒厂遗址", type: "风景名胜;旅游景点", distance: "2200" },
      { name: "华联购物中心", type: "购物服务;商场;购物中心", distance: "1800" },
      { name: "商丘师范大学", type: "科教文化服务;学校;高等院校", distance: "1400" }
    ],
    roadinters: [
      { first_name: "西郊北路", second_name: "庄周大道", distance: "1000" }
    ],
    addressComponent: {
      businessAreas: [{ name: "城南商圈", distance: "400" }]
    },
    aois: [
      {
        name: "高新产业园",
        type: "商务住宅;产业园区",
        area: "50000",
        distance: "100"
      },
      {
        name: "赵庄村",
        type: "地名地址信息;普通地名;村庄级地名",
        area: "50000",
        distance: "0"
      }
    ]
  });

  assert.deepEqual(candidates.map((candidate) => candidate.name), [
    "民生广场",
    "中心地铁站广场",
    "民权火车站广场",
    "葡萄酒厂遗址广场",
    "华联购物中心广场",
    "商丘师范大学广场",
    "西郊北路·庄周大道广场",
    "城南商圈广场",
    "高新产业园广场",
    "赵庄广场"
  ]);
});

test("preserves valid Amap coordinates and prefers an auditable duplicate", () => {
  const candidates = new PlazaNameSelector().select({
    aois: [
      {
        name: "民生广场",
        type: "风景名胜;公园广场;城市广场",
        distance: "10"
      }
    ],
    regionalPois: [
      {
        id: "B0FF123",
        name: "民生广场",
        type: "风景名胜;公园广场;城市广场",
        distance: "200",
        location: "115.1550363,34.6395154"
      },
      {
        name: "损坏坐标广场",
        type: "风景名胜;公园广场;城市广场",
        location: "not-a-coordinate"
      }
    ]
  });

  const selected = candidates.find((candidate) => candidate.name === "民生广场");
  assert.deepEqual(selected?.point, {
    coordinateSystem: "gcj02",
    longitude: 115.1550363,
    latitude: 34.6395154
  });
  assert.equal(selected?.providerPlaceId, "B0FF123");
  assert.equal(
    candidates.find((candidate) => candidate.name === "损坏坐标广场")?.point,
    undefined
  );
});
