import { Injectable } from "@nestjs/common";
import { ProfileRepository } from "./profile.repository.js";
import {
  ProfileDomainError,
  type Gender,
  type PrivacyPatch,
  type PrivacySettingsView,
  type ProfilePatch,
  type ProfileView
} from "./profile.types.js";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const GENDERS = new Set<Gender>(["unspecified", "male", "female", "custom"]);

@Injectable()
export class ProfileService {
  constructor(private readonly repository: ProfileRepository) {}

  getMine(userId: string): Promise<ProfileView> {
    return this.repository.getProfile(userId, userId);
  }

  getUser(viewerUserId: string, targetUserId: unknown): Promise<ProfileView> {
    return this.repository.getProfile(
      viewerUserId,
      this.uuid(targetUserId, "USER_ID_INVALID")
    );
  }

  updateMine(input: {
    userId: string;
    body: Record<string, unknown>;
    idempotencyKey?: string;
  }): Promise<ProfileView> {
    this.idempotencyKey(input.idempotencyKey);
    const body = input.body;
    const expectedVersion = body.expectedVersion;
    if (
      typeof expectedVersion !== "number" ||
      !Number.isInteger(expectedVersion) ||
      expectedVersion < 1
    ) {
      throw new ProfileDomainError(
        "PROFILE_VERSION_INVALID",
        "资料版本无效，请刷新后重试",
        400
      );
    }

    const patch: ProfilePatch = { expectedVersion };
    let changed = false;
    if (Object.hasOwn(body, "nickname")) {
      if (typeof body.nickname !== "string") {
        throw new ProfileDomainError(
          "PROFILE_NICKNAME_INVALID",
          "昵称格式无效",
          400
        );
      }
      const nickname = body.nickname.trim();
      if (!nickname || nickname.length > 64) {
        throw new ProfileDomainError(
          "PROFILE_NICKNAME_INVALID",
          "昵称应为1至64个字符",
          422
        );
      }
      patch.nickname = nickname;
      changed = true;
    }
    if (Object.hasOwn(body, "gender")) {
      if (typeof body.gender !== "string" || !GENDERS.has(body.gender as Gender)) {
        throw new ProfileDomainError(
          "PROFILE_GENDER_INVALID",
          "性别选项无效",
          400
        );
      }
      patch.gender = body.gender as Gender;
      changed = true;
    }
    if (Object.hasOwn(body, "customGender")) {
      if (
        body.customGender !== null &&
        (typeof body.customGender !== "string" ||
          !body.customGender.trim() ||
          body.customGender.trim().length > 32)
      ) {
        throw new ProfileDomainError(
          "PROFILE_CUSTOM_GENDER_INVALID",
          "自定义性别应为1至32个字符",
          422
        );
      }
      patch.customGender =
        body.customGender === null ? null : (body.customGender as string).trim();
      changed = true;
    }
    if (Object.hasOwn(body, "signature")) {
      if (typeof body.signature !== "string" || body.signature.trim().length > 160) {
        throw new ProfileDomainError(
          "PROFILE_SIGNATURE_INVALID",
          "个人签名不能超过160个字符",
          422
        );
      }
      patch.signature = body.signature.trim();
      changed = true;
    }
    if (
      Object.hasOwn(body, "avatarMediaId") ||
      Object.hasOwn(body, "backgroundMediaId")
    ) {
      throw new ProfileDomainError(
        "PROFILE_MEDIA_NOT_READY",
        "头像和背景墙将在媒体上传功能完成后开放",
        422
      );
    }
    if (!changed) {
      throw new ProfileDomainError(
        "PROFILE_UPDATE_EMPTY",
        "没有需要修改的资料",
        400
      );
    }
    if (patch.gender === "custom" && !patch.customGender) {
      throw new ProfileDomainError(
        "PROFILE_CUSTOM_GENDER_REQUIRED",
        "请选择自定义性别时需要填写内容",
        422
      );
    }
    if (patch.gender && patch.gender !== "custom") {
      patch.customGender = null;
    }
    return this.repository.updateProfile(input.userId, patch, new Date());
  }

  getPrivacy(userId: string): Promise<PrivacySettingsView> {
    return this.repository.getPrivacy(userId);
  }

  updatePrivacy(input: {
    userId: string;
    body: Record<string, unknown>;
    idempotencyKey?: string;
  }): Promise<PrivacySettingsView> {
    this.idempotencyKey(input.idempotencyKey);
    const allowed = [
      "strangersCanViewProfile",
      "searchableByFangyuanNumber",
      "globalGroupMuted"
    ] as const;
    const patch: PrivacyPatch = {};
    for (const key of allowed) {
      if (!Object.hasOwn(input.body, key)) continue;
      if (typeof input.body[key] !== "boolean") {
        throw new ProfileDomainError(
          "PRIVACY_SETTING_INVALID",
          "隐私设置无效",
          400
        );
      }
      patch[key] = input.body[key] as boolean;
    }
    if (Object.keys(patch).length === 0) {
      throw new ProfileDomainError(
        "PRIVACY_UPDATE_EMPTY",
        "没有需要修改的隐私设置",
        400
      );
    }
    return this.repository.updatePrivacy(input.userId, patch, new Date());
  }

  private uuid(value: unknown, code: string): string {
    if (typeof value !== "string" || !UUID_PATTERN.test(value)) {
      throw new ProfileDomainError(code, "标识格式无效", 400);
    }
    return value;
  }

  private idempotencyKey(value?: string): void {
    if (!value?.trim() || value.length > 200) {
      throw new ProfileDomainError(
        "IDEMPOTENCY_KEY_REQUIRED",
        "请求缺少有效的幂等键",
        400
      );
    }
  }
}
