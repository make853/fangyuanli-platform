import assert from "node:assert/strict";
import test from "node:test";
import {
  LocationContextError,
  LocationContextReader,
  type LocationSnapshot
} from "./location-context.js";

const userId = "019f0000-0000-7000-8000-00000000000a";
const snapshot: LocationSnapshot = {
  coordinateSystem: "gcj02",
  longitude: 113.264385,
  latitude: 23.129112,
  accuracyMeters: 18,
  capturedAt: new Date("2026-08-02T08:00:00.000Z"),
  expiresAt: new Date("2026-08-02T08:10:00.000Z")
};

test("encrypts a location snapshot and resolves it only for its owner", async () => {
  const reader = LocationContextReader.withKeyForTesting(Buffer.alloc(32, 7));
  const token = reader.issue({ userId, snapshot });

  assert.match(token, /^loc1_[A-Za-z0-9_-]+$/);
  assert.equal(token.includes(String(snapshot.longitude)), false);
  assert.deepEqual(
    await reader.resolve({
      token,
      userId,
      now: new Date("2026-08-02T08:01:00.000Z")
    }),
    snapshot
  );
  await assert.rejects(
    reader.resolve({
      token,
      userId: "019f0000-0000-7000-8000-00000000000b",
      now: new Date("2026-08-02T08:01:00.000Z")
    }),
    (error: unknown) =>
      error instanceof LocationContextError &&
      error.code === "LOCATION_CONTEXT_INVALID"
  );
});

test("rejects expired and tampered location tokens", async () => {
  const reader = LocationContextReader.withKeyForTesting(Buffer.alloc(32, 8));
  const token = reader.issue({ userId, snapshot });

  await assert.rejects(
    reader.resolve({
      token,
      userId,
      now: new Date("2026-08-02T08:11:00.000Z")
    }),
    (error: unknown) =>
      error instanceof LocationContextError &&
      error.code === "LOCATION_CONTEXT_EXPIRED"
  );
  await assert.rejects(
    reader.resolve({
      token: `${token.slice(0, 24)}${token[24] === "A" ? "B" : "A"}${token.slice(25)}`,
      userId,
      now: new Date("2026-08-02T08:01:00.000Z")
    }),
    (error: unknown) =>
      error instanceof LocationContextError &&
      error.code === "LOCATION_CONTEXT_INVALID"
  );
});
