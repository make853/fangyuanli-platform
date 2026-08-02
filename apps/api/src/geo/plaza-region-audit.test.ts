import assert from "node:assert/strict";
import test from "node:test";
import { PlazaGridProjector } from "./plaza-grid-projector.js";
import {
  PlazaRegionAuditor,
  type PlazaRegionAuditEntryInput
} from "./plaza-region-audit.js";
import type { PlazaGridVersion } from "./plaza-context.types.js";

const version: PlazaGridVersion = {
  id: "019f0b00-0000-7000-8000-000000000010",
  version: 3,
  coordinateSystem: "gcj02",
  projectionKey: "gcj02-web-mercator-v1",
  sideLengthMeters: 2_000
};

const cells = [
  { gridX: 6_400, gridY: 2_100 },
  { gridX: 6_401, gridY: 2_100 },
  { gridX: 6_400, gridY: 2_101 },
  { gridX: 6_401, gridY: 2_101 }
] as const;

function entries(projector: PlazaGridProjector): PlazaRegionAuditEntryInput[] {
  return cells.map((cell, index) => ({
    ...cell,
    plazaId: `019f0b00-0000-7000-8000-0000000001${index}`,
    name: ["民生广场", "民权站广场", "逍遥苑广场", "民权北站站前广场"][index]!,
    namingSource: "venue",
    namingKind: index === 1 ? "transit" : "public_square",
    namingPoint: projector.center(cell, version)
  }));
}

test("audits four distinct plazas and reports their directions", () => {
  const projector = new PlazaGridProjector();
  const auditor = new PlazaRegionAuditor(projector);
  const report = auditor.build({
    generatedAt: new Date("2026-08-03T00:00:00.000Z"),
    version,
    anchorPoint: projector.center(cells[0], version),
    plazas: entries(projector)
  });

  assert.equal(report.allNamedLandmarksInsideOwnCell, true);
  assert.deepEqual(
    report.plazas.map((plaza) => plaza.direction),
    ["当前位置", "东", "北", "东北"]
  );
  assert.ok(report.plazas.every((plaza) => plaza.landmarkInsideCell === true));
});

test("flags a landmark borrowed from a neighboring plaza", () => {
  const projector = new PlazaGridProjector();
  const auditor = new PlazaRegionAuditor(projector);
  const plazas = entries(projector);
  plazas[0] = {
    ...plazas[0]!,
    name: "错误的跨格地标广场",
    namingPoint: projector.center(cells[1], version)
  };

  const report = auditor.build({
    generatedAt: new Date("2026-08-03T00:00:00.000Z"),
    version,
    anchorPoint: projector.center(cells[0], version),
    plazas
  });
  const svg = auditor.renderSvg(report);

  assert.equal(report.allNamedLandmarksInsideOwnCell, false);
  assert.equal(report.plazas[0]?.landmarkInsideCell, false);
  assert.match(svg, /归属检查失败：存在跨方格地标/u);
  assert.match(svg, /错误的跨格地标广场/u);
  assert.doesNotMatch(svg, /019f0b00-0000-7000-8000/u);
});

test("keeps neutral fallbacks valid without inventing a landmark coordinate", () => {
  const projector = new PlazaGridProjector();
  const auditor = new PlazaRegionAuditor(projector);
  const plazas = entries(projector);
  plazas[3] = {
    ...plazas[3]!,
    name: "区域广场 7A2C",
    namingSource: "neutral",
    namingKind: null,
    namingPoint: null
  };

  const report = auditor.build({
    generatedAt: new Date("2026-08-03T00:00:00.000Z"),
    version,
    anchorPoint: projector.center(cells[0], version),
    plazas
  });
  const svg = auditor.renderSvg(report);

  assert.equal(report.allNamedLandmarksInsideOwnCell, true);
  assert.equal(report.plazas[3]?.landmarkInsideCell, null);
  assert.match(svg, /中性名称/u);
  assert.match(svg, /中性兜底/u);
});

test("rejects incomplete or duplicated four-plaza snapshots", () => {
  const projector = new PlazaGridProjector();
  const auditor = new PlazaRegionAuditor(projector);
  const complete = entries(projector);
  const input = {
    generatedAt: new Date("2026-08-03T00:00:00.000Z"),
    version,
    anchorPoint: projector.center(cells[0], version)
  };

  assert.throws(
    () => auditor.build({ ...input, plazas: complete.slice(0, 3) }),
    /exactly four plazas/u
  );
  assert.throws(
    () => auditor.build({ ...input, plazas: [complete[0]!, complete[0]!, complete[2]!, complete[3]!] }),
    /four distinct cells/u
  );
});
