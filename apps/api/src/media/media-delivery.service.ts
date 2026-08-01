import { Injectable } from "@nestjs/common";
import { ObjectStorageAdapter } from "./media.storage.js";
import {
  MediaDeliveryError,
  type MediaDeliveryReference,
  type MediaView
} from "./media.types.js";

const PROFILE_MEDIA_URL_TTL_SECONDS = 10 * 60;

@Injectable()
export class MediaDeliveryService {
  constructor(private readonly storage: ObjectStorageAdapter) {}

  async createView(reference: MediaDeliveryReference): Promise<MediaView> {
    if (reference.status !== "ready") {
      return this.view(reference, null, null, null, null);
    }
    if (!reference.displayObjectKey) {
      throw new MediaDeliveryError(
        "MEDIA_DERIVATIVE_MISSING",
        "媒体展示文件尚未准备完成"
      );
    }

    try {
      const [display, thumbnail, cover] = await Promise.all([
        this.storage.createReadTicket({
          objectKey: reference.displayObjectKey,
          expiresInSeconds: PROFILE_MEDIA_URL_TTL_SECONDS
        }),
        reference.thumbnailObjectKey
          ? this.storage.createReadTicket({
              objectKey: reference.thumbnailObjectKey,
              expiresInSeconds: PROFILE_MEDIA_URL_TTL_SECONDS
            })
          : null,
        reference.coverObjectKey
          ? this.storage.createReadTicket({
              objectKey: reference.coverObjectKey,
              expiresInSeconds: PROFILE_MEDIA_URL_TTL_SECONDS
            })
          : null
      ]);
      const expirations = [display, thumbnail, cover]
        .filter((ticket) => ticket !== null)
        .map((ticket) => ticket.expiresAt.getTime());
      return this.view(
        reference,
        display.url,
        thumbnail?.url ?? null,
        cover?.url ?? null,
        new Date(Math.min(...expirations)).toISOString()
      );
    } catch (error) {
      if (error instanceof MediaDeliveryError) throw error;
      throw new MediaDeliveryError(
        "MEDIA_DELIVERY_UNAVAILABLE",
        "媒体暂时无法加载，请稍后重试"
      );
    }
  }

  private view(
    reference: MediaDeliveryReference,
    url: string | null,
    thumbnailUrl: string | null,
    coverUrl: string | null,
    expiresAt: string | null
  ): MediaView {
    return {
      mediaId: reference.mediaId,
      mediaType: reference.mediaType,
      status: reference.status,
      url,
      thumbnailUrl,
      coverUrl,
      width: reference.width,
      height: reference.height,
      durationMs: reference.durationMs,
      expiresAt
    };
  }
}
