import assert from "node:assert/strict";
import test from "node:test";
import { PlazaGridProjector } from "./plaza-grid-projector.js";
import type { PlazaGridVersion } from "./plaza-context.types.js";

const version: PlazaGridVersion = {
  id: "019f0b00-0000-7000-8000-000000000001",
  version: 1,
  coordinateSystem: "gcj02",
  projectionKey: "gcj02-web-mercator-v1",
  sideLengthMeters: 500
};

test("returns one main cell and three deterministic corner neighbors", () => {
  const projector = new PlazaGridProjector();
  const main = { gridX: 25_000, gridY: 7_000 };
  const point = projector.center(main, version);

  const first = projector.cellsFor(point, version);
  const second = projector.cellsFor(point, version);

  assert.deepEqual(first, second);
  assert.deepEqual(first[0], main);
  assert.equal(new Set(first.map((cell) => `${cell.gridX}:${cell.gridY}`)).size, 4);
  assert.deepEqual(
    new Set(first.slice(1).map((cell) => `${cell.gridX - main.gridX}:${cell.gridY - main.gridY}`)),
    new Set(["1:0", "0:1", "1:1"])
  );
});
test("round trips grid centers and measures short GCJ-02 distances", () => {
  const projector = new PlazaGridProjector();
  const cell = { gridX: -10_000, gridY: 5_000 };
  const center = projector.center(cell, version);

  assert.deepEqual(projector.cellsFor(center, version)[0], cell);
  assert.ok(
    projector.distanceMeters(center, {
      ...center,
      latitude: center.latitude + 0.001
    }) > 100
  );
});
