import { Injectable } from "@nestjs/common";
import {
  GeoDomainError,
  type GeoContextRequest,
  type MotionState
} from "./plaza-context.types.js";

const MOTION_STATES = new Set<MotionState>([
  "stationary",
  "walking",
  "running",
  "driving",
  "unknown"
]);

@Injectable()
export class GeoContextInput {
  parse(body: Record<string, unknown>, now: Date): GeoContextRequest {
    const coordinateSystem = body.coordinateSystem;
    const longitude = this.number(body.longitude);
    const latitude = this.number(body.latitude);
    const accuracyMeters = this.number(body.accuracyMeters);
    const capturedAt = new Date(String(body.capturedAt ?? ""));
    const motionState = (body.motionState ?? "unknown") as MotionState;

    if (
      coordinateSystem !== "gcj02" ||
      longitude === null ||
      longitude < -180 ||
      longitude > 180 ||
      latitude === null ||
      latitude < -90 ||
      latitude > 90 ||
      accuracyMeters === null ||
      accuracyMeters < 0 ||
      accuracyMeters > 10_000 ||
      !Number.isFinite(capturedAt.getTime()) ||
      !MOTION_STATES.has(motionState)
    ) {
      throw new GeoDomainError(
        "GEO_CONTEXT_INPUT_INVALID",
        "定位数据格式无效",
        422
      );
    }

    const ageMs = now.getTime() - capturedAt.getTime();
    if (ageMs > 2 * 60_000 || ageMs < -30_000) {
      throw new GeoDomainError(
        "GEO_CONTEXT_LOCATION_STALE",
        "定位信息已过期，请重新定位",
        422
      );
    }

    return {
      coordinateSystem,
      longitude,
      latitude,
      accuracyMeters,
      capturedAt,
      motionState
    };
  }

  private number(value: unknown): number | null {
    return typeof value === "number" && Number.isFinite(value) ? value : null;
  }
}
