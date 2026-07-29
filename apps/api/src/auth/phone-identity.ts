import {
  createCipheriv,
  createHmac,
  randomBytes
} from "node:crypto";
import { AuthDomainError } from "./auth.types.js";

const CHINA_MOBILE_PATTERN = /^1[3-9]\d{9}$/;

function required(environment: NodeJS.ProcessEnv, name: string): string {
  const value = environment[name]?.trim();
  if (!value) {
    throw new Error(`${name} is required`);
  }
  return value;
}

function decodeKey(value: string): Buffer {
  const key = Buffer.from(value, "base64");
  if (key.length !== 32) {
    throw new Error("PHONE_ENCRYPTION_KEY must be a base64 encoded 32-byte key");
  }
  return key;
}

export type PhoneIdentity = {
  countryCode: "+86";
  ciphertext: string;
  hash: string;
  lastFour: string;
};

export class PhoneIdentityService {
  constructor(private readonly environment: NodeJS.ProcessEnv = process.env) {}

  create(countryCode: string, phoneNumber: string): PhoneIdentity {
    const normalized = phoneNumber.replace(/\s+/g, "");
    const isStagingAlias = this.isStagingAlias(normalized);

    if (countryCode !== "+86" || (!CHINA_MOBILE_PATTERN.test(normalized) && !isStagingAlias)) {
      throw new AuthDomainError(
        "AUTH_PHONE_INVALID",
        "请输入有效的中国大陆手机号码",
        400
      );
    }

    const hash = isStagingAlias
      ? this.stagingHash(normalized)
      : createHmac("sha256", required(this.environment, "PHONE_HASH_KEY"))
          .update(`+86:${normalized}`)
          .digest("hex");

    return {
      countryCode: "+86",
      ciphertext: this.encrypt(normalized),
      hash,
      lastFour: normalized.slice(-4).padStart(4, "0")
    };
  }

  hashCode(verificationId: string, code: string): string {
    return createHmac(
      "sha256",
      required(this.environment, "SMS_CODE_HASH_KEY")
    )
      .update(`${verificationId}:${code}`)
      .digest("hex");
  }

  hashValue(value: string, secretName: string): string {
    return createHmac("sha256", required(this.environment, secretName))
      .update(value)
      .digest("hex");
  }

  isStagingSmsEnabled(): boolean {
    return (
      this.environment.NODE_ENV === "staging" &&
      this.environment.ALLOW_STAGING_SMS === "true"
    );
  }

  stagingCode(): string {
    if (!this.isStagingSmsEnabled()) {
      throw new AuthDomainError(
        "SMS_PROVIDER_UNAVAILABLE",
        "短信服务尚未配置",
        503
      );
    }
    return required(this.environment, "STAGING_SMS_TEST_CODE");
  }

  private isStagingAlias(phoneNumber: string): boolean {
    if (!this.isStagingSmsEnabled()) {
      return false;
    }
    return [this.environment.STAGING_TEST_PHONE_A, this.environment.STAGING_TEST_PHONE_B]
      .filter(Boolean)
      .includes(phoneNumber);
  }

  private stagingHash(phoneNumber: string): string {
    if (phoneNumber === this.environment.STAGING_TEST_PHONE_A) {
      return "staging-test-only:phone-hash-a";
    }
    if (phoneNumber === this.environment.STAGING_TEST_PHONE_B) {
      return "staging-test-only:phone-hash-b";
    }
    throw new AuthDomainError("AUTH_PHONE_INVALID", "测试手机号未配置", 400);
  }

  private encrypt(phoneNumber: string): string {
    const iv = randomBytes(12);
    const cipher = createCipheriv(
      "aes-256-gcm",
      decodeKey(required(this.environment, "PHONE_ENCRYPTION_KEY")),
      iv
    );
    const encrypted = Buffer.concat([
      cipher.update(phoneNumber, "utf8"),
      cipher.final()
    ]);
    return [
      "v1",
      iv.toString("base64"),
      cipher.getAuthTag().toString("base64"),
      encrypted.toString("base64")
    ].join(".");
  }
}
