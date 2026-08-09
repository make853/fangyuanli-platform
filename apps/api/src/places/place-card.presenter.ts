import { Injectable } from "@nestjs/common";
import { displayDistance } from "./place-distance.js";
import type {
  PlaceCard,
  PlaceHeatLevel,
  PlaceProjection
} from "./place.types.js";

const HEAT_DISPLAY: Record<PlaceHeatLevel, string> = {
  quiet: "冷清",
  neutral: "中性",
  active: "活跃",
  veryActive: "非常活跃",
  hot: "火爆"
};

@Injectable()
export class PlaceCardPresenter {
  present(projection: PlaceProjection, meters: number): PlaceCard {
    const unreadCount = Math.max(
      0,
      projection.latestSequence - projection.lastReadSequence
    );
    const isManager = projection.role === "owner" || projection.role === "admin";
    const isMember =
      isManager || projection.role === "resident" || projection.role === "member";
    const withinSpeakRange = meters <= projection.visibilityRadiusMeters;
    const canSpeak =
      isManager ||
      (projection.speakPolicy === "nearbyAndMembers" && withinSpeakRange) ||
      (projection.speakPolicy === "membersOnly" && isMember);
    return {
      placeGroupId: projection.placeGroupId,
      conversationId: projection.conversationId,
      name: projection.name,
      image: projection.providerPhotoUrl
        ? {
            source: "amap",
            url: projection.providerPhotoUrl,
            title: projection.providerPhotoTitle
          }
        : null,
      category: { key: projection.categoryKey, name: projection.categoryName },
      distance: { meters, display: displayDistance(meters) },
      certificationStatus: projection.certificationStatus,
      heat: {
        level: projection.heatLevel,
        display: HEAT_DISPLAY[projection.heatLevel]
      },
      unread: {
        count: unreadCount,
        appearance:
          unreadCount === 0
            ? "none"
            : projection.notificationMode === "muted"
              ? "gray"
              : "red",
        firstUnreadSequence:
          unreadCount === 0 ? null : projection.lastReadSequence + 1
      },
      allowedActions: [
        "viewDetail",
        "enterConversation",
        ...(canSpeak ? ["sendMessage"] : []),
        ...(isManager ? ["managePlace"] : [])
      ],
      version: projection.version
    };
  }
}
