import { Injectable } from "@nestjs/common";
import type { Gcj02Point } from "./location-context.js";
import type { PlazaCell, PlazaGridVersion } from "./plaza-context.types.js";

const EARTH_RADIUS_METERS = 6_378_137;
const MAX_MERCATOR_LATITUDE = 85.05112878;

type ProjectedPoint = { x: number; y: number };

/**
 * Versioned technical projection for the first square-grid rollout.
 *
 * Input and output coordinates remain explicitly GCJ-02. Web Mercator is used
 * only to obtain stable planar grid indexes. The grid version keeps this
 * replaceable after real-device/Amap distance validation.
 */
@Injectable()
export class PlazaGridProjector {
  cellsFor(point: Gcj02Point, version: PlazaGridVersion): PlazaCell[] {
    if (version.projectionKey !== "gcj02-web-mercator-v1") {
      throw new Error(`Unsupported plaza projection: ${version.projectionKey}`);
    }
    const projected = this.project(point);
    const side = version.sideLengthMeters;
    const gridX = Math.floor(projected.x / side);
    const gridY = Math.floor(projected.y / side);
    const localX = projected.x - gridX * side;
    const localY = projected.y - gridY * side;
    const xDirection = localX >= side / 2 ? 1 : -1;
    const yDirection = localY >= side / 2 ? 1 : -1;
    const horizontal = { gridX: gridX + xDirection, gridY };
    const vertical = { gridX, gridY: gridY + yDirection };
    const diagonal = {
      gridX: gridX + xDirection,
      gridY: gridY + yDirection
    };
    const xBoundaryDistance = xDirection > 0 ? side - localX : localX;
    const yBoundaryDistance = yDirection > 0 ? side - localY : localY;
    const adjacent = [
      { cell: horizontal, distance: xBoundaryDistance },
      { cell: vertical, distance: yBoundaryDistance },
      {
        cell: diagonal,
        distance: Math.hypot(xBoundaryDistance, yBoundaryDistance)
      }
    ].sort(
      (left, right) =>
        left.distance - right.distance || this.key(left.cell).localeCompare(this.key(right.cell))
    );
    return [{ gridX, gridY }, ...adjacent.map(({ cell }) => cell)];
  }

  center(cell: PlazaCell, version: PlazaGridVersion): Gcj02Point {
    const side = version.sideLengthMeters;
    return this.unproject({
      x: (cell.gridX + 0.5) * side,
      y: (cell.gridY + 0.5) * side
    });
  }

  distanceMeters(left: Gcj02Point, right: Gcj02Point): number {
    const latitude1 = (left.latitude * Math.PI) / 180;
    const latitude2 = (right.latitude * Math.PI) / 180;
    const latitudeDelta = latitude2 - latitude1;
    const longitudeDelta = ((right.longitude - left.longitude) * Math.PI) / 180;
    const haversine =
      Math.sin(latitudeDelta / 2) ** 2 +
      Math.cos(latitude1) * Math.cos(latitude2) * Math.sin(longitudeDelta / 2) ** 2;
    return 2 * EARTH_RADIUS_METERS * Math.asin(Math.min(1, Math.sqrt(haversine)));
  }

  private project(point: Gcj02Point): ProjectedPoint {
    const latitude = Math.max(
      -MAX_MERCATOR_LATITUDE,
      Math.min(MAX_MERCATOR_LATITUDE, point.latitude)
    );
    return {
      x: EARTH_RADIUS_METERS * (point.longitude * Math.PI) / 180,
      y:
        EARTH_RADIUS_METERS *
        Math.log(Math.tan(Math.PI / 4 + (latitude * Math.PI) / 360))
    };
  }

  private unproject(point: ProjectedPoint): Gcj02Point {
    return {
      coordinateSystem: "gcj02",
      longitude: (point.x / EARTH_RADIUS_METERS) * (180 / Math.PI),
      latitude:
        (2 * Math.atan(Math.exp(point.y / EARTH_RADIUS_METERS)) - Math.PI / 2) *
        (180 / Math.PI)
    };
  }

  private key(cell: PlazaCell): string {
    return `${cell.gridX}:${cell.gridY}`;
  }
}
