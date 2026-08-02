import { chmod, mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import pg from "pg";
import {
  loadRepositoryEnvironment,
  requireDatabaseUrl
} from "../src/database/environment.js";
import { PlazaGridProjector } from "../src/geo/plaza-grid-projector.js";
import { PlazaRegionAuditor } from "../src/geo/plaza-region-audit.js";
import { parsePlazaRegionAuditArguments } from "../src/geo/plaza-region-audit-command.js";
import type {
  PlazaGridVersion,
  PlazaAnchor
} from "../src/geo/plaza-context.types.js";
import type {
  PlazaNamingKind,
  PlazaNamingSource
} from "../src/geo/plaza-naming.provider.js";

const { Client } = pg;

type AnchorAuditRow = {
  user_id: string;
  grid_version_id: string;
  anchor_longitude_gcj02: string;
  anchor_latitude_gcj02: string;
  plaza_ids: string[];
  version: number;
  coordinate_system: "gcj02";
  projection_key: "gcj02-web-mercator-v1";
  side_length_meters: number;
};

type PlazaAuditRow = {
  plaza_id: string;
  display_name: string;
  grid_x: string;
  grid_y: string;
  naming_source: PlazaNamingSource | "neutral";
  naming_kind: PlazaNamingKind | null;
  naming_longitude_gcj02: string | null;
  naming_latitude_gcj02: string | null;
};

loadRepositoryEnvironment();

if (process.env.NODE_ENV === "production") {
  throw new Error("Plaza region auditing is disabled in production");
}

const arguments_ = parsePlazaRegionAuditArguments(process.argv.slice(2));
const client = new Client({
  application_name: "fangyuanli-plaza-region-audit",
  connectionString: requireDatabaseUrl(process.env)
});

await client.connect();

try {
  const anchorResult = await client.query<AnchorAuditRow>(
    `SELECT anchor.user_id,
            anchor.grid_version_id,
            anchor.anchor_longitude_gcj02,
            anchor.anchor_latitude_gcj02,
            anchor.plaza_ids,
            version.version,
            version.coordinate_system,
            version.projection_key,
            version.side_length_meters
       FROM user_plaza_anchors anchor
       JOIN plaza_grid_versions version ON version.id = anchor.grid_version_id
      WHERE ($1::uuid IS NULL OR anchor.user_id = $1)
      ORDER BY anchor.updated_at DESC
      LIMIT 1`,
    [arguments_.userId]
  );
  const anchor = anchorResult.rows[0];
  if (!anchor) throw new Error("No plaza anchor matched the requested account");

  const plazasResult = await client.query<PlazaAuditRow>(
    `SELECT grid.id AS plaza_id,
            grid.display_name,
            grid.grid_x,
            grid.grid_y,
            grid.naming_source,
            grid.naming_kind,
            grid.naming_longitude_gcj02,
            grid.naming_latitude_gcj02
       FROM unnest($1::uuid[]) WITH ORDINALITY AS selected(plaza_id, position)
       JOIN plaza_grids grid ON grid.id = selected.plaza_id
      ORDER BY selected.position`,
    [anchor.plaza_ids]
  );

  const version: PlazaGridVersion = {
    id: anchor.grid_version_id,
    version: anchor.version,
    coordinateSystem: anchor.coordinate_system,
    projectionKey: anchor.projection_key,
    sideLengthMeters: anchor.side_length_meters
  };
  const anchorPoint: PlazaAnchor["point"] = {
    coordinateSystem: "gcj02",
    longitude: Number(anchor.anchor_longitude_gcj02),
    latitude: Number(anchor.anchor_latitude_gcj02)
  };
  const auditor = new PlazaRegionAuditor(new PlazaGridProjector());
  const report = auditor.build({
    generatedAt: new Date(),
    version,
    anchorPoint,
    plazas: plazasResult.rows.map((row) => ({
      plazaId: row.plaza_id,
      name: row.display_name,
      gridX: Number(row.grid_x),
      gridY: Number(row.grid_y),
      namingSource: row.naming_source,
      namingKind: row.naming_kind,
      namingPoint:
        row.naming_longitude_gcj02 === null || row.naming_latitude_gcj02 === null
          ? null
          : {
              coordinateSystem: "gcj02",
              longitude: Number(row.naming_longitude_gcj02),
              latitude: Number(row.naming_latitude_gcj02)
            }
    }))
  });

  await mkdir(path.dirname(arguments_.output), { recursive: true });
  await writeFile(arguments_.output, auditor.renderSvg(report), {
    encoding: "utf8",
    mode: 0o600
  });
  await chmod(arguments_.output, 0o600);
  console.log(`Plaza region audit written to ${arguments_.output}`);
  console.log(
    report.allNamedLandmarksInsideOwnCell
      ? "Containment result: PASS"
      : "Containment result: FAIL"
  );
} finally {
  await client.end();
}
