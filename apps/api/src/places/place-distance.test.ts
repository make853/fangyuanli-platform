import assert from "node:assert/strict";
import test from "node:test";
import { displayDistance, distanceMeters } from "./place-distance.js";

test("calculates a stable short-range distance without changing coordinate systems", () => {
  const meters = distanceMeters(
    { coordinateSystem: "gcj02", longitude: 113.264385, latitude: 23.129112 },
    { coordinateSystem: "gcj02", longitude: 113.265385, latitude: 23.129112 }
  );
  assert.ok(meters >= 100 && meters <= 105);
});

test("formats nearby and kilometer distances for cards", () => {
  assert.equal(displayDistance(380), "约380米");
  assert.equal(displayDistance(1260), "约1.3公里");
  assert.equal(displayDistance(12_600), "约13公里");
});
