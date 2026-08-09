import { Injectable } from "@nestjs/common";

export type PlazaPolicyValues = {
  version: number;
  anchorRadiusMeters: number;
  maximumAccuracyMeters: number;
  locationContextTtlMilliseconds: number;
};

@Injectable()
export class PlazaPolicy {
  constructor(private readonly environment: NodeJS.ProcessEnv = process.env) {}

  values(): PlazaPolicyValues {
    return {
      version: 2,
      anchorRadiusMeters: this.integer("PLAZA_ANCHOR_RADIUS_METERS", 150, 50, 500),
      maximumAccuracyMeters: this.integer(
        "PLAZA_MAXIMUM_ACCURACY_METERS",
        80,
        10,
        500
      ),
      locationContextTtlMilliseconds:
        this.integer("LOCATION_CONTEXT_TTL_SECONDS", 600, 60, 1_800) * 1_000
    };
  }

  private integer(name: string, fallback: number, minimum: number, maximum: number): number {
    const raw = this.environment[name]?.trim();
    const value = raw ? Number(raw) : fallback;
    if (!Number.isInteger(value) || value < minimum || value > maximum) {
      throw new Error(`${name} must be an integer between ${minimum} and ${maximum}`);
    }
    return value;
  }
}
