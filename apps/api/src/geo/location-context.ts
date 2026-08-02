import { Injectable } from "@nestjs/common";
import {
  createCipheriv,
  createDecipheriv,
  randomBytes
} from "node:crypto";

export type Gcj02Point = {
  coordinateSystem: "gcj02";
  longitude: number;
  latitude: number;
};

export type LocationSnapshot = Gcj02Point & {
  accuracyMeters: number;
  capturedAt: Date;
  expiresAt: Date;
  authorizedPlazaIds?: string[];
};

export class LocationContextError extends Error {
  constructor(
    public readonly code: string,
    message: string,
    public readonly status: number
  ) {
    super(message);
  }
}

/**
 * Stable boundary consumed by geo-aware business modules.
 *
 * Places must not decode tokens or accept raw coordinates itself. The future
 * geo module can change token storage/cryptography without changing place
 * discovery rules.
 */
@Injectable()
export class LocationContextReader {
  private testingKey?: Buffer;

  static withKeyForTesting(key: Buffer): LocationContextReader {
    const reader = new LocationContextReader();
    reader.testingKey = Buffer.from(key);
    return reader;
  }

  issue(input: { userId: string; snapshot: LocationSnapshot }): string {
    this.validateSnapshot(input.snapshot);
    if (!input.userId.trim()) {
      throw new LocationContextError(
        "LOCATION_CONTEXT_USER_INVALID",
        "位置上下文用户无效",
        400
      );
    }
    const payload = Buffer.from(
      JSON.stringify({
        version: 1,
        userId: input.userId,
        coordinateSystem: input.snapshot.coordinateSystem,
        longitude: input.snapshot.longitude,
        latitude: input.snapshot.latitude,
        accuracyMeters: input.snapshot.accuracyMeters,
        capturedAt: input.snapshot.capturedAt.toISOString(),
        expiresAt: input.snapshot.expiresAt.toISOString(),
        authorizedPlazaIds: input.snapshot.authorizedPlazaIds ?? null
      }),
      "utf8"
    );
    const nonce = randomBytes(12);
    const cipher = createCipheriv("aes-256-gcm", this.key(), nonce);
    cipher.setAAD(Buffer.from("fangyuanli-location-context-v1", "utf8"));
    const encrypted = Buffer.concat([cipher.update(payload), cipher.final()]);
    const tag = cipher.getAuthTag();
    return `loc1_${Buffer.concat([nonce, tag, encrypted]).toString("base64url")}`;
  }

  async resolve(input: {
    token: string;
    userId: string;
    now: Date;
  }): Promise<LocationSnapshot> {
    try {
      // Four authorized plaza UUIDs make the encrypted v1 token slightly
      // larger than the original coordinate-only envelope.
      if (!input.token.startsWith("loc1_") || input.token.length > 2_048) {
        throw new Error("unsupported token");
      }
      const packed = Buffer.from(input.token.slice(5), "base64url");
      if (packed.length <= 28) throw new Error("truncated token");
      const nonce = packed.subarray(0, 12);
      const tag = packed.subarray(12, 28);
      const encrypted = packed.subarray(28);
      const decipher = createDecipheriv("aes-256-gcm", this.key(), nonce);
      decipher.setAAD(Buffer.from("fangyuanli-location-context-v1", "utf8"));
      decipher.setAuthTag(tag);
      const payload = JSON.parse(
        Buffer.concat([decipher.update(encrypted), decipher.final()]).toString("utf8")
      ) as Record<string, unknown>;
      if (payload.version !== 1 || payload.userId !== input.userId) {
        throw new Error("token owner mismatch");
      }
      const authorizedPlazaIds = Array.isArray(payload.authorizedPlazaIds)
        ? payload.authorizedPlazaIds as string[]
        : undefined;
      const snapshot: LocationSnapshot = {
        coordinateSystem: payload.coordinateSystem as "gcj02",
        longitude: payload.longitude as number,
        latitude: payload.latitude as number,
        accuracyMeters: payload.accuracyMeters as number,
        capturedAt: new Date(payload.capturedAt as string),
        expiresAt: new Date(payload.expiresAt as string),
        ...(authorizedPlazaIds ? { authorizedPlazaIds } : {})
      };
      this.validateSnapshot(snapshot);
      if (snapshot.expiresAt.getTime() <= input.now.getTime()) {
        throw new LocationContextError(
          "LOCATION_CONTEXT_EXPIRED",
          "定位已过期，请刷新后重试",
          401
        );
      }
      return snapshot;
    } catch (error) {
      if (error instanceof LocationContextError) throw error;
      throw new LocationContextError(
        "LOCATION_CONTEXT_INVALID",
        "定位凭证无效，请刷新后重试",
        401
      );
    }
  }

  private key(): Buffer {
    if (this.testingKey) {
      if (this.testingKey.length !== 32) throw new Error("Location key must be 32 bytes");
      return this.testingKey;
    }
    const encoded = process.env.FANGYUANLI_LOCATION_CONTEXT_KEY?.trim();
    if (!encoded) {
      throw new LocationContextError(
        "LOCATION_CONTEXT_UNAVAILABLE",
        "位置上下文服务尚未配置",
        503
      );
    }
    const decoded = Buffer.from(encoded, "base64url");
    if (decoded.length !== 32) {
      throw new LocationContextError(
        "LOCATION_CONTEXT_UNAVAILABLE",
        "位置上下文服务配置无效",
        503
      );
    }
    return decoded;
  }

  private validateSnapshot(snapshot: LocationSnapshot): void {
    if (
      snapshot.coordinateSystem !== "gcj02" ||
      !Number.isFinite(snapshot.longitude) ||
      snapshot.longitude < -180 ||
      snapshot.longitude > 180 ||
      !Number.isFinite(snapshot.latitude) ||
      snapshot.latitude < -90 ||
      snapshot.latitude > 90 ||
      !Number.isFinite(snapshot.accuracyMeters) ||
      snapshot.accuracyMeters < 0 ||
      snapshot.accuracyMeters > 10_000 ||
      !Number.isFinite(snapshot.capturedAt.getTime()) ||
      !Number.isFinite(snapshot.expiresAt.getTime()) ||
      snapshot.expiresAt <= snapshot.capturedAt ||
      snapshot.expiresAt.getTime() - snapshot.capturedAt.getTime() > 30 * 60_000 ||
      (snapshot.authorizedPlazaIds !== undefined &&
        (snapshot.authorizedPlazaIds.length !== 4 ||
          new Set(snapshot.authorizedPlazaIds).size !== 4 ||
          snapshot.authorizedPlazaIds.some(
            (plazaId) => typeof plazaId !== "string" || !plazaId.trim()
          )))
    ) {
      throw new LocationContextError(
        "LOCATION_CONTEXT_DATA_INVALID",
        "定位数据无效",
        422
      );
    }
  }
}
