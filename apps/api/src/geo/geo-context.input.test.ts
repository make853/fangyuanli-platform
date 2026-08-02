import assert from "node:assert/strict";
import test from "node:test";
import { GeoContextInput } from "./geo-context.input.js";
import { GeoDomainError } from "./plaza-context.types.js";

const now = new Date("2026-08-02T10:00:00.000Z");

test("parses a fresh GCJ-02 location without coercing input values", () => {
  const parsed = new GeoContextInput().parse(
    {
      coordinateSystem: "gcj02",
      longitude: 121.4737,
      latitude: 31.2304,
      accuracyMeters: 18,
      capturedAt: "2026-08-02T09:59:30.000Z",
      motionState: "walking"
    },
    now
  );

  assert.equal(parsed.coordinateSystem, "gcj02");
  assert.equal(parsed.motionState, "walking");
  assert.equal(parsed.capturedAt.toISOString(), "2026-08-02T09:59:30.000Z");
});
test("rejects stale, future and non-GCJ-02 location input", () => {
  const parser = new GeoContextInput();
  for (const body of [
    {
      coordinateSystem: "wgs84",
      longitude: 121.4737,
      latitude: 31.2304,
      accuracyMeters: 18,
      capturedAt: now.toISOString()
    },
    {
      coordinateSystem: "gcj02",
      longitude: 121.4737,
      latitude: 31.2304,
      accuracyMeters: 18,
      capturedAt: "2026-08-02T09:57:00.000Z"
    },
    {
      coordinateSystem: "gcj02",
      longitude: 121.4737,
      latitude: 31.2304,
      accuracyMeters: 18,
      capturedAt: "2026-08-02T10:01:00.000Z"
    }
  ]) {
    assert.throws(
      () => parser.parse(body, now),
      (error: unknown) => error instanceof GeoDomainError && error.status === 422
    );
  }
});
