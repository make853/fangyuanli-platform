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
  let requestedUrl: URL | null = null;
  const provider = new AmapPlazaNamingProvider(new PlazaNameSelector(), {
    environment: { AMAP_WEB_SERVICE_KEY: "test-key" },
    fetcher: async (input) => {
      requestedUrl = new URL(String(input));
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

  assert.equal(requestedUrl?.origin, "https://restapi.amap.com");
  assert.equal(requestedUrl?.searchParams.get("location"), "121.473701,31.230402");
  assert.equal(requestedUrl?.searchParams.get("extensions"), "all");
  assert.equal(requestedUrl?.searchParams.get("radius"), "1200");
  assert.equal(candidates[0]?.name, "滨江体育中心广场");
});
