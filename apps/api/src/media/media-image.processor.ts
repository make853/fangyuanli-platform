import { Injectable } from "@nestjs/common";
import sharp, { type FitEnum, type Sharp } from "sharp";
import { ObjectStorageAdapter } from "./media.storage.js";
import {
  MediaProcessingError,
  type MediaProcessingJob,
  type MediaProcessingResult
} from "./media-processing.types.js";

const MAX_INPUT_PIXELS = 40_000_000;
const WEBP_QUALITY = 84;

type VariantSpec = {
  name: string;
  width: number;
  height: number;
  fit: keyof FitEnum;
};

type EncodedVariant = {
  objectKey: string;
  body: Buffer;
  width: number;
  height: number;
};

@Injectable()
export class MediaImageProcessor {
  constructor(private readonly storage: ObjectStorageAdapter) {}

  async process(job: MediaProcessingJob): Promise<MediaProcessingResult> {
    if (job.mediaType !== "image") {
      throw new MediaProcessingError(
        "MEDIA_PROCESSING_TYPE_UNSUPPORTED",
        "当前 Worker 只处理图片",
        false
      );
    }

    let source: Buffer;
    try {
      source = (await this.storage.getObject(job.sourceObjectKey)).body;
    } catch {
      throw new MediaProcessingError(
        "MEDIA_SOURCE_UNAVAILABLE",
        "暂时无法读取原始媒体",
        true
      );
    }

    let variants: [EncodedVariant, EncodedVariant];
    try {
      variants = await this.encodeVariants(job, source);
    } catch (error) {
      if (error instanceof MediaProcessingError) throw error;
      throw new MediaProcessingError(
        "MEDIA_IMAGE_INVALID",
        "图片无法安全解码或处理",
        false
      );
    }

    try {
      for (const variant of variants) {
        await this.storage.putObject({
          objectKey: variant.objectKey,
          contentType: "image/webp",
          body: variant.body
        });
      }
    } catch {
      throw new MediaProcessingError(
        "MEDIA_DERIVATIVE_WRITE_FAILED",
        "派生图片暂时无法写入存储",
        true
      );
    }

    const [display, thumbnail] = variants;
    return {
      displayObjectKey: display.objectKey,
      thumbnailObjectKey: thumbnail.objectKey,
      width: display.width,
      height: display.height,
      displayBytes: display.body.byteLength
    };
  }

  private async encodeVariants(
    job: MediaProcessingJob,
    source: Buffer
  ): Promise<[EncodedVariant, EncodedVariant]> {
    const image = sharp(source, {
      failOn: "warning",
      limitInputPixels: MAX_INPUT_PIXELS
    }).rotate();
    const metadata = await image.metadata();
    if (!metadata.width || !metadata.height) {
      throw new MediaProcessingError(
        "MEDIA_IMAGE_DIMENSIONS_INVALID",
        "图片缺少有效尺寸",
        false
      );
    }
    const [displaySpec, thumbnailSpec] = this.specs(job);
    const prefix = `processed/${job.ownerUserId}/${job.mediaId}`;
    const display = await this.encode(
      image.clone(),
      displaySpec,
      `${prefix}/${displaySpec.name}.webp`
    );
    const thumbnail = await this.encode(
      image.clone(),
      thumbnailSpec,
      `${prefix}/${thumbnailSpec.name}.webp`
    );
    return [display, thumbnail];
  }

  private specs(job: MediaProcessingJob): [VariantSpec, VariantSpec] {
    if (job.purpose === "avatar") {
      return [
        { name: "avatar-512", width: 512, height: 512, fit: "cover" },
        { name: "avatar-128", width: 128, height: 128, fit: "cover" }
      ];
    }
    if (job.purpose === "background") {
      return [
        { name: "background-1920", width: 1920, height: 1920, fit: "inside" },
        { name: "background-480", width: 480, height: 480, fit: "inside" }
      ];
    }
    return [
      { name: "image-2560", width: 2560, height: 2560, fit: "inside" },
      { name: "image-480", width: 480, height: 480, fit: "inside" }
    ];
  }

  private async encode(
    image: Sharp,
    spec: VariantSpec,
    objectKey: string
  ): Promise<EncodedVariant> {
    const { data, info } = await image
      .resize({
        width: spec.width,
        height: spec.height,
        fit: spec.fit,
        position: "centre",
        withoutEnlargement: true
      })
      .webp({ quality: WEBP_QUALITY, effort: 4 })
      .toBuffer({ resolveWithObject: true });
    if (!info.width || !info.height || data.byteLength === 0) {
      throw new MediaProcessingError(
        "MEDIA_IMAGE_OUTPUT_INVALID",
        "派生图片输出无效",
        false
      );
    }
    return {
      objectKey,
      body: data,
      width: info.width,
      height: info.height
    };
  }
}
