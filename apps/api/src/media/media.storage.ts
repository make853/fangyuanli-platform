import { Injectable } from "@nestjs/common";
import COS from "cos-nodejs-sdk-v5";

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

@Injectable()
export class CosObjectStorageAdapter extends ObjectStorageAdapter {
  private client: COS | null = null;

  async createUploadTicket(input: {
    objectKey: string;
    contentType: string;
    expiresInSeconds: number;
  }): Promise<ObjectUploadTicket> {
    const { bucket, region } = this.configuration();
    const url = this.cos().getObjectUrl({
      Bucket: bucket,
      Region: region,
      Key: input.objectKey,
      Method: "PUT",
      Sign: true,
      Expires: input.expiresInSeconds,
      Protocol: "https:"
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
    const secretId = process.env.TENCENT_COS_SECRET_ID?.trim();
    const secretKey = process.env.TENCENT_COS_SECRET_KEY?.trim();
    if (!secretId || !secretKey) {
      throw new Error(
        "TENCENT_COS_SECRET_ID and TENCENT_COS_SECRET_KEY are required"
      );
    }
    this.client = new COS({ SecretId: secretId, SecretKey: secretKey });
    return this.client;
  }

  private configuration(): { bucket: string; region: string } {
    const bucket = process.env.TENCENT_COS_BUCKET?.trim();
    const region = process.env.TENCENT_COS_REGION?.trim();
    if (!bucket || !region) {
      throw new Error("TENCENT_COS_BUCKET and TENCENT_COS_REGION are required");
    }
    return { bucket, region };
  }

  private normalizeEtag(value: string): string {
    return value.trim().replace(/^"|"$/g, "");
  }
}
