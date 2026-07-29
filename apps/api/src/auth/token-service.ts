import { createHmac, randomBytes } from "node:crypto";
import { jwtVerify, SignJWT } from "jose";
import type { AuthTokens } from "./auth.types.js";

const ACCESS_TTL_SECONDS = 15 * 60;
const REFRESH_TTL_SECONDS = 30 * 24 * 60 * 60;

function secret(environment: NodeJS.ProcessEnv, name: string): Uint8Array {
  const value = environment[name]?.trim();
  if (!value || value.length < 32) {
    throw new Error(`${name} must contain at least 32 characters`);
  }
  return new TextEncoder().encode(value);
}

export type AccessClaims = {
  userId: string;
  sessionId: string;
  deviceId: string;
  tokenVersion: number;
};

export class TokenService {
  constructor(private readonly environment: NodeJS.ProcessEnv = process.env) {}

  createRefreshToken(): string {
    return randomBytes(48).toString("base64url");
  }

  createDeterministicRefreshToken(verificationId: string, idempotencyKey: string): string {
    return createHmac(
      "sha256",
      secret(this.environment, "AUTH_REFRESH_TOKEN_SECRET")
    )
      .update(`login:${verificationId}:${idempotencyKey}`)
      .digest("base64url");
  }

  hashRefreshToken(token: string): string {
    return createHmac(
      "sha256",
      secret(this.environment, "AUTH_REFRESH_TOKEN_SECRET")
    )
      .update(token)
      .digest("hex");
  }

  async issueTokens(
    claims: AccessClaims,
    refreshToken: string,
    now = new Date()
  ): Promise<AuthTokens> {
    const accessExpiresAt = new Date(now.getTime() + ACCESS_TTL_SECONDS * 1000);
    const refreshExpiresAt = new Date(now.getTime() + REFRESH_TTL_SECONDS * 1000);
    const accessToken = await new SignJWT({
      sid: claims.sessionId,
      did: claims.deviceId,
      ver: claims.tokenVersion
    })
      .setProtectedHeader({ alg: "HS256" })
      .setSubject(claims.userId)
      .setIssuedAt(Math.floor(now.getTime() / 1000))
      .setExpirationTime(Math.floor(accessExpiresAt.getTime() / 1000))
      .sign(secret(this.environment, "AUTH_ACCESS_TOKEN_SECRET"));

    return {
      accessToken,
      accessTokenExpiresAt: accessExpiresAt.toISOString(),
      refreshToken,
      refreshTokenExpiresAt: refreshExpiresAt.toISOString()
    };
  }

  async verifyAccessToken(token: string): Promise<AccessClaims> {
    const { payload } = await jwtVerify(
      token,
      secret(this.environment, "AUTH_ACCESS_TOKEN_SECRET")
    );
    if (
      !payload.sub ||
      typeof payload.sid !== "string" ||
      typeof payload.did !== "string" ||
      typeof payload.ver !== "number"
    ) {
      throw new Error("Invalid access token claims");
    }
    return {
      userId: payload.sub,
      sessionId: payload.sid,
      deviceId: payload.did,
      tokenVersion: payload.ver
    };
  }
}
