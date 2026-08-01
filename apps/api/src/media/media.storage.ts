import COS from "cos-nodejs-sdk-v5";

const CVM_METADATA_BASE =
  "http://metadata.tencentyun.com/latest/meta-data/cam/security-credentials";
const ROLE_NAME_PATTERN = /^[A-Za-z0-9._-]{1,64}$/;

export type CredentialFetcher = typeof fetch;

type CvmRoleCredentialResponse = {
  TmpSecretId?: unknown;
  TmpSecretKey?: unknown;
  ExpiredTime?: unknown;
  Token?: unknown;
  Code?: unknown;
};

export type CosTemporaryCredentials = {
  TmpSecretId: string;
  TmpSecretKey: string;
  SecurityToken: string;
  StartTime: number;
  ExpiredTime: number;
  ScopeLimit: false;
};

export class CvmRoleCredentialSource {
  constructor(
    private readonly roleName: string,
    private readonly fetcher: CredentialFetcher = fetch
  ) {
    if (!ROLE_NAME_PATTERN.test(roleName)) {
      throw new Error("TENCENT_COS_CVM_ROLE is invalid");
    }
  }

  async load(): Promise<CosTemporaryCredentials> {
    const response = await this.fetcher(
      `${CVM_METADATA_BASE}/${encodeURIComponent(this.roleName)}`,
      { signal: AbortSignal.timeout(3_000) }
    );
    if (!response.ok) {
      throw new Error(
        `CVM role credentials are unavailable (${response.status})`
      );
    }
    const payload = (await response.json()) as CvmRoleCredentialResponse;
    const tmpSecretId = this.nonEmpty(payload.TmpSecretId);
    const tmpSecretKey = this.nonEmpty(payload.TmpSecretKey);
    const securityToken = this.nonEmpty(payload.Token);
    const expiredTime = Number(payload.ExpiredTime);
    const now = Math.floor(Date.now() / 1000);
    if (
      payload.Code !== "Success" ||
      !tmpSecretId ||
      !tmpSecretKey ||
      !securityToken ||
      !Number.isSafeInteger(expiredTime) ||
      expiredTime <= now + 60
    ) {
      throw new Error("CVM role returned invalid or expiring credentials");
    }
    return {
      TmpSecretId: tmpSecretId,
      TmpSecretKey: tmpSecretKey,
      SecurityToken: securityToken,
      StartTime: now - 5,
      ExpiredTime: expiredTime,
      ScopeLimit: false
    };
  }

  private nonEmpty(value: unknown): string | null {
    return typeof value === "string" && value.trim() ? value.trim() : null;
  }
}

export type ObjectUploadTicket = {
  method: "PUT";
  url: string;
  headers: Record<string, string>;
};

export type StoredObjectMetadata = {
  bytes: number;
  etag: string;
};

export abstract class ObjectStorageAdapter {
  abstract createUploadTicket(input: {
    objectKey: string;
    contentType: string;
    expiresInSeconds: number;
  }): Promise<ObjectUploadTicket>;

  abstract headObject(objectKey: string): Promise<StoredObjectMetadata | null>;

  abstract deleteObject(objectKey: string): Promise<void>;
}

export type CosObjectStorageAdapterOptions = {
  environment?: NodeJS.ProcessEnv;
  credentialFetcher?: CredentialFetcher;
};

export class CosObjectStorageAdapter extends ObjectStorageAdapter {
  private client: COS | null = null;
  private readonly environment: NodeJS.ProcessEnv;
  private readonly credentialFetcher: CredentialFetcher;

  constructor(options: CosObjectStorageAdapterOptions = {}) {
    super();
    this.environment = options.environment ?? process.env;
    this.credentialFetcher = options.credentialFetcher ?? fetch;
  }

  async createUploadTicket(input: {
    objectKey: string;
    contentType: string;
    expiresInSeconds: number;
  }): Promise<ObjectUploadTicket> {
    const { bucket, region } = this.configuration();
    const url = await new Promise<string>((resolve, reject) => {
      this.cos().getObjectUrl(
        {
          Bucket: bucket,
          Region: region,
          Key: input.objectKey,
          Method: "PUT",
          Sign: true,
          Expires: input.expiresInSeconds,
          Protocol: "https:"
        },
        (error, result) => {
          if (error) return reject(error);
          if (!result?.Url) {
            return reject(new Error("COS did not return a signed upload URL"));
          }
          resolve(result.Url);
        }
      );
    });
    return {
      method: "PUT",
      url,
      headers: { "Content-Type": input.contentType }
    };
  }

  async headObject(objectKey: string): Promise<StoredObjectMetadata | null> {
    const { bucket, region } = this.configuration();
    try {
      const result = await this.cos().headObject({
        Bucket: bucket,
        Region: region,
        Key: objectKey
      });
      const rawLength =
        result.headers?.["content-length"] ?? result.headers?.["Content-Length"];
      const bytes = Number(rawLength);
      if (!Number.isSafeInteger(bytes) || bytes < 0) {
        throw new Error("COS returned an invalid content length");
      }
      return { bytes, etag: this.normalizeEtag(result.ETag) };
    } catch (error) {
      if (
        typeof error === "object" &&
        error !== null &&
        "statusCode" in error &&
        (error as { statusCode?: number }).statusCode === 404
      ) {
        return null;
      }
      throw error;
    }
  }

  async deleteObject(objectKey: string): Promise<void> {
    const { bucket, region } = this.configuration();
    await this.cos().deleteObject({
      Bucket: bucket,
      Region: region,
      Key: objectKey
    });
  }

  private cos(): COS {
    if (this.client) return this.client;
    const roleName = this.environment.TENCENT_COS_CVM_ROLE?.trim();
    if (roleName) {
      const credentialSource = new CvmRoleCredentialSource(
        roleName,
        this.credentialFetcher
      );
      this.client = new COS({
        getAuthorization: (_options, callback) => {
          void credentialSource
            .load()
            .then((credentials) => callback(credentials))
            .catch(() => callback(""));
        }
      });
      return this.client;
    }
    const secretId = this.environment.TENCENT_COS_SECRET_ID?.trim();
    const secretKey = this.environment.TENCENT_COS_SECRET_KEY?.trim();
    if (!secretId || !secretKey) {
      throw new Error(
        "TENCENT_COS_CVM_ROLE or COS SecretId/SecretKey is required"
      );
    }
    this.client = new COS({ SecretId: secretId, SecretKey: secretKey });
    return this.client;
  }

  private configuration(): { bucket: string; region: string } {
    const bucket = this.environment.TENCENT_COS_BUCKET?.trim();
    const region = this.environment.TENCENT_COS_REGION?.trim();
    if (!bucket || !region) {
      throw new Error("TENCENT_COS_BUCKET and TENCENT_COS_REGION are required");
    }
    return { bucket, region };
  }

  private normalizeEtag(value: string): string {
    return value.trim().replace(/^"|"$/g, "");
  }
}
