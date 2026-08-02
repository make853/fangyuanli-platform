import assert from "node:assert/strict";
import test from "node:test";
import { AmapPlazaNamingProvider } from "./amap-plaza-naming.provider.js";
import { PlazaNameSelector } from "./plaza-name-selector.js";

const point = {
  coordinateSystem: "gcj02" as const,
  longitude: 121.4737012,
  latitude: 31.2304018
};

test("stays disabled without a server-side Amap key", async () => {
  let requested = false;
  const provider = new AmapPlazaNamingProvider(new PlazaNameSelector(), {
    environment: {},
    fetcher: async () => {
      requested = true;
      return new Response();
    }
  });

  assert.equal(provider.isConfigured(), false);
  assert.deepEqual(await provider.candidates(point), []);
  assert.equal(requested, false);
});

test("requests GCJ-02 reverse geocoding and returns ranked stable names", async () => {
  const requestedUrls: URL[] = [];
  const provider = new AmapPlazaNamingProvider(new PlazaNameSelector(), {
    environment: { AMAP_WEB_SERVICE_KEY: "test-key" },
    fetcher: async (input) => {
      const requestedUrl = new URL(String(input));
      requestedUrls.push(requestedUrl);
      if (requestedUrl.pathname === "/v5/place/around") {
        return Response.json({
          status: "1",
          info: "OK",
          pois: [
            {
              name: "滨江城市广场",
              type: "风景名胜;公园广场;城市广场",
              distance: "500"
            }
          ]
        });
      }
      return Response.json({
        status: "1",
        info: "OK",
        regeocode: {
          aois: [
            {
              name: "滨江体育中心",
              type: "体育休闲服务;体育场馆",
              area: "85000",
              distance: "30"
            }
          ],
          pois: []
        }
      });
    }
  });

  assert.equal(provider.isConfigured(), true);
  const candidates = await provider.candidates(point);

  assert.equal(requestedUrls.length, 2);
  const reverseUrl = requestedUrls.find((url) => url.pathname === "/v3/geocode/regeo");
  const aroundUrl = requestedUrls.find((url) => url.pathname === "/v5/place/around");
  assert.equal(reverseUrl?.origin, "https://restapi.amap.com");
  assert.equal(reverseUrl?.searchParams.get("location"), "121.473701,31.230402");
  assert.equal(reverseUrl?.searchParams.get("extensions"), "all");
  assert.equal(reverseUrl?.searchParams.get("radius"), "1600");
  assert.equal(aroundUrl?.searchParams.get("radius"), "3000");
  assert.equal(aroundUrl?.searchParams.get("sortrule"), "distance");
  assert.equal(aroundUrl?.searchParams.get("page_size"), "25");
  assert.equal(candidates[0]?.name, "滨江体育中心广场");
  assert.equal(
    candidates.some((candidate) => candidate.name === "滨江城市广场"),
    true
  );
});

test("uses regional landmarks when reverse geocoding is unavailable", async () => {
  const provider = new AmapPlazaNamingProvider(new PlazaNameSelector(), {
    environment: { AMAP_WEB_SERVICE_KEY: "test-key" },
    fetcher: async (input) => {
      const requestedUrl = new URL(String(input));
      if (requestedUrl.pathname === "/v3/geocode/regeo") {
        return new Response(null, { status: 503 });
      }
      return Response.json({
        status: "1",
        info: "OK",
        pois: [
          {
            name: "民生广场",
            type: "风景名胜;公园广场;城市广场",
            distance: "800"
          }
        ]
      });
    }
  });

  assert.equal((await provider.candidates(point))[0]?.name, "民生广场");
});
