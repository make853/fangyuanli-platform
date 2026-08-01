import { Injectable } from "@nestjs/common";
import { randomUUID } from "node:crypto";
import { DatabaseService } from "../database/database.service.js";
import { AuthDomainError, type DeviceInput } from "./auth.types.js";
import type { PhoneIdentity } from "./phone-identity.js";
import type { AccessClaims } from "./token-service.js";

const REFRESH_TTL_MS = 30 * 24 * 60 * 60 * 1000;

type VerificationRow = {
  id: string;
  code_hash: string;
  attempts: number;
  expires_at: Date;
  resend_after: Date;
  consumed_at: Date | null;
  phone_hash: string;
  phone_ciphertext: string;
  phone_last_four: string;
};

export type SessionResult = {
  userId: string;
  sessionId: string;
  deviceId: string;
  tokenVersion: number;
  isNewUser: boolean;
};

@Injectable()
export class AuthRepository {
  constructor(private readonly database: DatabaseService) {}

  async findLatestVerification(phoneHash: string): Promise<{ resendAfter: Date } | null> {
    const result = await this.database.query<{ resend_after: Date }>(
      `SELECT resend_after
         FROM sms_verifications
        WHERE phone_hash = $1
        ORDER BY created_at DESC
        LIMIT 1`,
      [phoneHash]
    );
    return result.rows[0] ? { resendAfter: result.rows[0].resend_after } : null;
  }

  async createVerification(
    identity: PhoneIdentity,
    codeHash: string,
    now: Date,
    id = randomUUID()
  ): Promise<{ id: string; expiresAt: Date; resendAfter: Date }> {
    const expiresAt = new Date(now.getTime() + 5 * 60 * 1000);
    const resendAfter = new Date(now.getTime() + 60 * 1000);
    await this.database.query(
      `INSERT INTO sms_verifications (
         id, country_code, phone_ciphertext, phone_hash, phone_last_four,
         purpose, code_hash, expires_at, resend_after, created_at
       ) VALUES ($1, $2, $3, $4, $5, 'login', $6, $7, $8, $9)`,
      [
        id,
        identity.countryCode,
        identity.ciphertext,
        identity.hash,
        identity.lastFour,
        codeHash,
        expiresAt,
        resendAfter,
        now
      ]
    );
    return { id, expiresAt, resendAfter };
  }

  async verifyAndCreateSession(input: {
    verificationId: string;
    codeHash: string;
    idempotencyKeyHash: string;
    refreshTokenHash: string;
    device: DeviceInput;
    now: Date;
  }): Promise<SessionResult> {
    try {
      return await this.database.transaction(async (client) => {
      const verificationResult = await client.query<VerificationRow>(
        `SELECT *
           FROM sms_verifications
          WHERE id = $1
          FOR UPDATE`,
        [input.verificationId]
      );
      const verification = verificationResult.rows[0];
      if (!verification) {
        throw new AuthDomainError("AUTH_VERIFICATION_NOT_FOUND", "验证码请求不存在", 404);
      }

      if (verification.consumed_at) {
        const existing = await client.query<{
          user_id: string;
          id: string;
          device_id: string;
          token_version: number;
          login_created_user: boolean;
          login_idempotency_key_hash: string | null;
          revoked_at: Date | null;
        }>(
          `SELECT user_id, id, device_id, token_version, login_created_user,
                  login_idempotency_key_hash, revoked_at
             FROM auth_sessions
            WHERE source_verification_id = $1`,
          [verification.id]
        );
        const session = existing.rows[0];
        if (
          !session ||
          session.login_idempotency_key_hash !== input.idempotencyKeyHash ||
          session.token_version !== 1 ||
          session.revoked_at
        ) {
          throw new AuthDomainError("AUTH_VERIFICATION_USED", "验证码已经使用", 409);
        }
        return {
          userId: session.user_id,
          sessionId: session.id,
          deviceId: session.device_id,
          tokenVersion: session.token_version,
          isNewUser: session.login_created_user
        };
      }

      if (verification.expires_at.getTime() <= input.now.getTime()) {
        throw new AuthDomainError("AUTH_CODE_EXPIRED", "验证码已过期，请重新获取", 410);
      }
      if (verification.attempts >= 5) {
        throw new AuthDomainError("AUTH_CODE_LOCKED", "验证次数过多，请重新获取验证码", 429);
      }
      if (verification.code_hash !== input.codeHash) {
        throw new AuthDomainError("AUTH_CODE_INVALID", "验证码错误", 400);
      }

      let userId: string;
      let isNewUser = false;
      const userResult = await client.query<{ id: string; status: string }>(
        `SELECT id, status FROM users WHERE phone_hash = $1 AND deleted_at IS NULL`,
        [verification.phone_hash]
      );
      if (userResult.rows[0]) {
        if (userResult.rows[0].status !== "active") {
          throw new AuthDomainError("AUTH_ACCOUNT_UNAVAILABLE", "账号当前不可登录", 403);
        }
        userId = userResult.rows[0].id;
      } else {
        isNewUser = true;
        userId = randomUUID();
        const fangyuanNumber = `FY${userId.replaceAll("-", "").slice(0, 12).toUpperCase()}`;
        await client.query(
          `INSERT INTO users (
             id, fangyuan_number, phone_ciphertext, phone_hash, status, created_at, updated_at
           ) VALUES ($1, $2, $3, $4, 'active', $5, $5)`,
          [
            userId,
            fangyuanNumber,
            verification.phone_ciphertext,
            verification.phone_hash,
            input.now
          ]
        );
        await client.query(
          `INSERT INTO user_profiles (user_id, nickname, updated_at)
           VALUES ($1, $2, $3)`,
          [userId, `方圆用户${verification.phone_last_four}`, input.now]
        );
        await client.query(
          `INSERT INTO user_privacy_settings (user_id, updated_at)
           VALUES ($1, $2)`,
          [userId, input.now]
        );
      }

      await client.query(
        `INSERT INTO user_devices (
           id, user_id, platform, device_name, last_active_at, revoked_at, created_at
         ) VALUES ($1, $2, $3, $4, $5, NULL, $5)
         ON CONFLICT (id, user_id) DO UPDATE
           SET platform = EXCLUDED.platform,
               device_name = EXCLUDED.device_name,
               last_active_at = EXCLUDED.last_active_at,
               revoked_at = NULL`,
        [
          input.device.deviceId,
          userId,
          input.device.platform,
          input.device.deviceName ?? null,
          input.now
        ]
      );

      const sessionId = randomUUID();
      await client.query(
        `INSERT INTO auth_sessions (
           id, user_id, device_id, refresh_token_hash, token_version,
           expires_at, source_verification_id, login_idempotency_key_hash,
           login_created_user, created_at
         ) VALUES ($1, $2, $3, $4, 1, $5, $6, $7, $8, $9)`,
        [
          sessionId,
          userId,
          input.device.deviceId,
          input.refreshTokenHash,
          new Date(input.now.getTime() + REFRESH_TTL_MS),
          verification.id,
          input.idempotencyKeyHash,
          isNewUser,
          input.now
        ]
      );
      await client.query(
        `UPDATE sms_verifications SET consumed_at = $2 WHERE id = $1`,
        [verification.id, input.now]
      );
      return {
        userId,
        sessionId,
        deviceId: input.device.deviceId,
        tokenVersion: 1,
        isNewUser
      };
      });
    } catch (error) {
      if (error instanceof AuthDomainError && error.code === "AUTH_CODE_INVALID") {
        await this.database.query(
          `UPDATE sms_verifications
              SET attempts = attempts + 1
            WHERE id = $1 AND consumed_at IS NULL`,
          [input.verificationId]
        );
      }
      throw error;
    }
  }

  async rotateSession(input: {
    deviceId: string;
    oldRefreshTokenHash: string;
    newRefreshTokenHash: string;
    now: Date;
  }): Promise<SessionResult> {
    return this.database.transaction(async (client) => {
      const result = await client.query<{
        id: string;
        user_id: string;
        device_id: string;
        token_version: number;
        expires_at: Date;
        revoked_at: Date | null;
      }>(
        `SELECT id, user_id, device_id, token_version, expires_at, revoked_at
           FROM auth_sessions
          WHERE refresh_token_hash = $1 AND device_id = $2
          FOR UPDATE`,
        [input.oldRefreshTokenHash, input.deviceId]
      );
      const session = result.rows[0];
      if (
        !session ||
        session.revoked_at ||
        session.expires_at.getTime() <= input.now.getTime()
      ) {
        throw new AuthDomainError("AUTH_REFRESH_INVALID", "登录状态已失效，请重新登录", 401);
      }
      const tokenVersion = session.token_version + 1;
      await client.query(
        `UPDATE auth_sessions
            SET refresh_token_hash = $2,
                token_version = $3,
                expires_at = $4,
                last_refreshed_at = $5
          WHERE id = $1`,
        [
          session.id,
          input.newRefreshTokenHash,
          tokenVersion,
          new Date(input.now.getTime() + REFRESH_TTL_MS),
          input.now
        ]
      );
      return {
        userId: session.user_id,
        sessionId: session.id,
        deviceId: session.device_id,
        tokenVersion,
        isNewUser: false
      };
    });
  }

  async revokeSession(input: {
    sessionId: string;
    userId: string;
    deviceId: string;
    tokenVersion: number;
    now: Date;
  }): Promise<void> {
    const result = await this.database.query(
      `UPDATE auth_sessions
          SET revoked_at = $5
        WHERE id = $1
          AND user_id = $2
          AND device_id = $3
          AND token_version = $4
          AND revoked_at IS NULL`,
      [
        input.sessionId,
        input.userId,
        input.deviceId,
        input.tokenVersion,
        input.now
      ]
    );
    if (result.rowCount !== 1) {
      const existing = await this.database.query(
        `SELECT 1
           FROM auth_sessions
          WHERE id = $1
            AND user_id = $2
            AND device_id = $3
            AND token_version = $4
            AND revoked_at IS NOT NULL`,
        [
          input.sessionId,
          input.userId,
          input.deviceId,
          input.tokenVersion
        ]
      );
      if (existing.rowCount !== 1) {
        throw new AuthDomainError("AUTH_SESSION_INVALID", "登录状态已失效", 401);
      }
    }
  }

  async isSessionActive(claims: AccessClaims, now = new Date()): Promise<boolean> {
    const result = await this.database.query(
      `SELECT 1
         FROM auth_sessions
        WHERE id = $1
          AND user_id = $2
          AND device_id = $3
          AND token_version = $4
          AND revoked_at IS NULL
          AND expires_at > $5`,
      [
        claims.sessionId,
        claims.userId,
        claims.deviceId,
        claims.tokenVersion,
        now
      ]
    );
    return result.rowCount === 1;
  }

}
