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
