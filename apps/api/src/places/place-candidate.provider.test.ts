import assert from "node:assert/strict";
import test from "node:test";
import type { LocationSnapshot } from "../geo/location-context.js";
import {
  PlaceCandidateProvider,
  PlaceCandidateProviderError
} from "./place-candidate.provider.js";

const location: LocationSnapshot = {
  coordinateSystem: "gcj02",
  longitude: 116.4731684,
  latitude: 39.9930154,
  accuracyMeters: 10,
  capturedAt: new Date("2026-08-09T00:00:00.000Z"),
  expiresAt: new Date("2026-08-09T00:10:00.000Z")
};

test("stays disabled without a server-side Amap key", async () => {
  let requested = false;
  const provider = new PlaceCandidateProvider({
    environment: {},
    fetcher: async () => {
      requested = true;
      return Response.json({});
    }
  });

  assert.equal(provider.isConfigured(), false);
  assert.deepEqual(
    await provider.discover({
      location,
      radiusMeters: 5_000,
      keyword: null,
      categoryKeys: [],
      limit: 20
    }),
    []
  );
  assert.equal(requested, false);
});

test("requests Amap POIs with GCJ-02 coordinates and parses safe candidates", async () => {
  const requestedUrls: URL[] = [];
  const provider = new PlaceCandidateProvider({
    environment: { AMAP_WEB_SERVICE_KEY: "test-key" },
    now: () => new Date("2026-08-09T01:00:00.000Z"),
    fetcher: async (input) => {
      requestedUrls.push(new URL(String(input)));
      return Response.json({
        status: "1",
        info: "OK",
        pois: [
          {
            id: "B000A1",
            name: "隆江猪脚饭",
            address: "测试路1号",
            location: "116.474000,39.993600",
            type: "餐饮服务;中餐厅",
            typecode: "050100",
            photos: [
              { title: "无效图片", url: "javascript:alert(1)" },
              {
                title: "门店环境",
                url: "http://images.example.test/store.jpg"
              }
            ]
          },
          {
            id: "invalid-location",
            name: "无效地点",
            location: []
          }
        ]
      });
    }
  });

  const candidates = await provider.discover({
    location,
    radiusMeters: 4_000,
    keyword: "猪脚饭",
    categoryKeys: ["food_retail"],
    limit: 20
  });

  assert.equal(requestedUrls.length, 1);
  const url = requestedUrls[0];
  assert.equal(url?.origin, "https://restapi.amap.com");
  assert.equal(url?.pathname, "/v5/place/around");
  assert.equal(url?.searchParams.get("location"), "116.473168,39.993015");
  assert.equal(url?.searchParams.get("radius"), "4000");
  assert.equal(url?.searchParams.get("keywords"), "猪脚饭");
  assert.equal(url?.searchParams.get("types"), "050000|060000|070000");
  assert.equal(url?.searchParams.get("sortrule"), "weight");
  assert.equal(url?.searchParams.get("page_size"), "20");
  assert.equal(url?.searchParams.get("show_fields"), "photos");
  assert.deepEqual(candidates, [
    {
      provider: "amap",
      providerPlaceId: "B000A1",
      name: "隆江猪脚饭",
      address: "测试路1号",
      coordinateSystem: "gcj02",
      longitude: 116.474,
      latitude: 39.9936,
      rawCategoryCode: "050100",
      rawCategoryName: "餐饮服务;中餐厅",
      providerPhotoUrl: "https://images.example.test/store.jpg",
      providerPhotoTitle: "门店环境",
      sourceUpdatedAt: new Date("2026-08-09T01:00:00.000Z")
    }
  ]);
});

test("coalesces repeated discovery requests inside the short cache window", async () => {
  let requests = 0;
  const provider = new PlaceCandidateProvider({
    environment: { AMAP_WEB_SERVICE_KEY: "test-key" },
    fetcher: async () => {
      requests += 1;
      return Response.json({ status: "1", info: "OK", pois: [] });
    }
  });
  const request = {
    location,
    radiusMeters: 5_000,
    keyword: null,
    categoryKeys: [] as const,
    limit: 20
  };

  await Promise.all([
    provider.discover({ ...request, categoryKeys: [...request.categoryKeys] }),
    provider.discover({ ...request, categoryKeys: [...request.categoryKeys] })
  ]);
  await provider.discover({ ...request, categoryKeys: [...request.categoryKeys] });

  assert.equal(requests, 1);
});

test("rejects provider failures with a narrow external-boundary error", async () => {
  const provider = new PlaceCandidateProvider({
    environment: { AMAP_WEB_SERVICE_KEY: "test-key" },
    fetcher: async () => new Response(null, { status: 503 })
  });

  await assert.rejects(
    provider.discover({
      location,
      radiusMeters: 5_000,
      keyword: null,
      categoryKeys: [],
      limit: 20
    }),
    PlaceCandidateProviderError
  );
});
