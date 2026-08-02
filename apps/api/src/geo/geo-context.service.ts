import { Injectable } from "@nestjs/common";
import { GeoContextInput } from "./geo-context.input.js";
import {
  LocationContextError,
  LocationContextReader,
  type Gcj02Point
} from "./location-context.js";
import { PlazaAnchorPolicy } from "./plaza-anchor-policy.js";
import { PlazaContextRepository } from "./plaza-context.repository.js";
import { PlazaGridProjector } from "./plaza-grid-projector.js";
import { PlazaNamingService } from "./plaza-naming.service.js";
import {
  GeoDomainError,
  type GeoContextResult,
  type PlazaProjection,
  type PlazaSummary
} from "./plaza-context.types.js";
import { PlazaPolicy } from "./plaza-policy.js";

@Injectable()
export class GeoContextService {
  constructor(
    private readonly inputParser: GeoContextInput,
    private readonly repository: PlazaContextRepository,
    private readonly projector: PlazaGridProjector,
    private readonly anchorPolicy: PlazaAnchorPolicy,
    private readonly policyProvider: PlazaPolicy,
    private readonly locationContexts: LocationContextReader,
    private readonly naming: PlazaNamingService
  ) {}

  async create(input: {
    userId: string;
    body: Record<string, unknown>;
    now?: Date;
  }): Promise<GeoContextResult> {
    const now = input.now ?? new Date();
    const request = this.inputParser.parse(input.body, now);
    const policy = this.policyProvider.values();
    if (request.accuracyMeters > policy.maximumAccuracyMeters) {
      throw new GeoDomainError(
        "GEO_CONTEXT_ACCURACY_INSUFFICIENT",
        "当前定位精度不足，请移动到开阔位置后重试",
        422
      );
    }

    const version = await this.repository.activeGridVersion();
    const point: Gcj02Point = {
      coordinateSystem: "gcj02",
      longitude: request.longitude,
      latitude: request.latitude
    };
    const cells = this.projector.cellsFor(point, version);
    const candidates = await this.repository.ensurePlazas({
      userId: input.userId,
      version,
      cells
    });
    if (candidates.length !== 4) {
      throw new Error("Failed to resolve exactly four plaza grids");
    }
    void this.naming
      .enrich({ version, cells, plazas: candidates })
      .catch(() => undefined);

    return this.repository.serializeForUser(input.userId, async () => {
      const existing = await this.repository.findAnchor(input.userId);
      let decision = this.anchorPolicy.decide({
        userId: input.userId,
        gridVersionId: version.id,
        point,
        accuracyMeters: request.accuracyMeters,
        candidatePlazaIds: candidates.map((plaza) => plaza.plazaId),
        existing,
        now,
        policy
      });
      let selected = this.sameIds(
        decision.plazaIds,
        candidates.map((plaza) => plaza.plazaId)
      )
        ? candidates
        : await this.repository.findPlazasByIds({
            userId: input.userId,
            plazaIds: decision.plazaIds
          });
      if (selected.length !== 4) {
        decision = this.anchorPolicy.decide({
          userId: input.userId,
          gridVersionId: version.id,
          point,
          accuracyMeters: request.accuracyMeters,
          candidatePlazaIds: candidates.map((plaza) => plaza.plazaId),
          existing: null,
          now,
          policy
        });
        selected = candidates;
      }
      await this.repository.saveAnchor(decision.anchor);

      const expiresAt = new Date(now.getTime() + policy.locationContextTtlMilliseconds);
      let locationContextToken: string;
      try {
        locationContextToken = this.locationContexts.issue({
          userId: input.userId,
          snapshot: {
            ...point,
            accuracyMeters: request.accuracyMeters,
            capturedAt: request.capturedAt,
            expiresAt,
            authorizedPlazaIds: selected.map((plaza) => plaza.plazaId)
          }
        });
      } catch (error) {
        if (error instanceof LocationContextError) {
          throw new GeoDomainError(error.code, error.message, error.status);
        }
        throw error;
      }

      return {
        locationContextToken,
        expiresAt: expiresAt.toISOString(),
        anchor: {
          radiusMeters: policy.anchorRadiusMeters,
          isReused: decision.isReused,
          recalculationPending: decision.recalculationPending
        },
        plazas: selected.map((plaza, index) => this.present(plaza, index === 0))
      };
    });
  }

  private present(plaza: PlazaProjection, isMain: boolean): PlazaSummary {
    const unreadCount = plaza.unreadCount;
    return {
      plazaId: plaza.plazaId,
      conversationId: plaza.conversationId,
      name: plaza.name,
      relation: isMain ? "main" : "adjacent",
      canView: true,
      canSpeak: true,
      unread: {
        count: unreadCount,
        appearance:
          unreadCount === 0
            ? "none"
            : plaza.notificationMode === "muted"
              ? "gray"
              : "red",
        firstUnreadSequence: plaza.firstUnreadSequence
      }
    };
  }

  private sameIds(left: string[], right: string[]): boolean {
    return left.length === right.length && left.every((id, index) => id === right[index]);
  }
}
