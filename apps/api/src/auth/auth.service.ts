import { Injectable } from "@nestjs/common";
import { randomUUID } from "node:crypto";
import { AuthRepository } from "./auth.repository.js";
import {
  AuthDomainError,
  type AuthResponse,
  type DeviceInput,
  type SmsSendResponse
} from "./auth.types.js";
import { PhoneIdentityService } from "./phone-identity.js";
import { TokenService } from "./token-service.js";

@Injectable()
export class AuthService {
  private readonly phoneIdentity = new PhoneIdentityService();
  private readonly tokens = new TokenService();

  constructor(private readonly repository: AuthRepository) {}

  async sendSms(input: {
    countryCode?: unknown;
    phoneNumber?: unknown;
    purpose?: unknown;
  }): Promise<SmsSendResponse> {
    if (input.purpose !== "login") {
      throw new AuthDomainError("AUTH_PURPOSE_INVALID", "暂不支持此验证用途", 400);
    }
    if (typeof input.countryCode !== "string" || typeof input.phoneNumber !== "string") {
      throw new AuthDomainError("AUTH_PHONE_INVALID", "请输入手机号码", 400);
    }
    const identity = this.phoneIdentity.create(input.countryCode, input.phoneNumber);
    const now = new Date();
    const latest = await this.repository.findLatestVerification(identity.hash);
    if (latest && latest.resendAfter.getTime() > now.getTime()) {
      throw new AuthDomainError("AUTH_SMS_TOO_FREQUENT", "验证码发送过于频繁", 429);
    }

    // 第一阶段只开放 staging 明确配置的 A/B 测试号码；
    // 正式短信供应商接入后，此处替换为供应商发送结果。
    const code = this.phoneIdentity.stagingCode();
    const verificationId = randomUUID();
    const codeHash = this.phoneIdentity.hashCode(verificationId, code);
    const created = await this.repository.createVerification(
      identity,
      codeHash,
      now,
      verificationId
    );
    return {
      verificationId: created.id,
      expiresAt: created.expiresAt.toISOString(),
      resendAfterSeconds: Math.max(
        0,
        Math.ceil((created.resendAfter.getTime() - now.getTime()) / 1000)
      )
    };
  }

  async verifySms(input: {
    verificationId?: unknown;
    code?: unknown;
    device?: unknown;
    idempotencyKey?: string;
  }): Promise<AuthResponse> {
    if (
      typeof input.verificationId !== "string" ||
      typeof input.code !== "string" ||
      !/^\d{6}$/.test(input.code) ||
      !input.idempotencyKey ||
      input.idempotencyKey.length > 200
    ) {
      throw new AuthDomainError("AUTH_VERIFY_INVALID", "验证信息不完整", 400);
    }
    const device = this.parseDevice(input.device);
    const refreshToken = this.tokens.createDeterministicRefreshToken(
      input.verificationId,
      input.idempotencyKey
    );
    const session = await this.repository.verifyAndCreateSession({
      verificationId: input.verificationId,
      codeHash: this.phoneIdentity.hashCode(input.verificationId, input.code),
      idempotencyKeyHash: this.phoneIdentity.hashValue(
        input.idempotencyKey,
        "AUTH_REFRESH_TOKEN_SECRET"
      ),
      refreshTokenHash: this.tokens.hashRefreshToken(refreshToken),
      device,
      now: new Date()
    });
    const issued = await this.tokens.issueTokens(session, refreshToken);
    return { ...issued, ...session };
  }

  async refresh(input: {
    deviceId?: unknown;
    refreshToken?: unknown;
  }): Promise<AuthResponse> {
    if (typeof input.deviceId !== "string" || typeof input.refreshToken !== "string") {
      throw new AuthDomainError("AUTH_REFRESH_INVALID", "刷新登录信息不完整", 400);
    }
    const nextRefreshToken = this.tokens.createRefreshToken();
    const session = await this.repository.rotateSession({
      deviceId: input.deviceId,
      oldRefreshTokenHash: this.tokens.hashRefreshToken(input.refreshToken),
      newRefreshTokenHash: this.tokens.hashRefreshToken(nextRefreshToken),
      now: new Date()
    });
    const issued = await this.tokens.issueTokens(session, nextRefreshToken);
    return { ...issued, ...session };
  }

  async logout(input: {
    authorization?: string;
    deviceId?: string;
  }): Promise<void> {
    const token = input.authorization?.match(/^Bearer (.+)$/i)?.[1];
    if (!token || !input.deviceId) {
      throw new AuthDomainError("AUTH_REQUIRED", "请先登录", 401);
    }
    try {
      const claims = await this.tokens.verifyAccessToken(token);
      if (claims.deviceId !== input.deviceId) {
        throw new AuthDomainError("AUTH_DEVICE_MISMATCH", "设备信息不匹配", 401);
      }
      await this.repository.revokeSession({ ...claims, now: new Date() });
    } catch (error) {
      if (error instanceof AuthDomainError) {
        throw error;
      }
      throw new AuthDomainError("AUTH_REQUIRED", "登录状态已失效", 401);
    }
  }

  private parseDevice(value: unknown): DeviceInput {
    if (!value || typeof value !== "object") {
      throw new AuthDomainError("AUTH_DEVICE_INVALID", "设备信息不完整", 400);
    }
    const device = value as Record<string, unknown>;
    if (
      (device.platform !== "ios" && device.platform !== "android") ||
      typeof device.deviceName !== "string" ||
      device.deviceName.trim().length === 0 ||
      device.deviceName.length > 128
    ) {
      throw new AuthDomainError("AUTH_DEVICE_INVALID", "设备信息无效", 400);
    }
    return {
      deviceId: randomUUID(),
      platform: device.platform,
      deviceName: device.deviceName
    };
  }
}
