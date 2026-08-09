import { Injectable } from "@nestjs/common";
import {
  LocationContextError,
  LocationContextReader
} from "../geo/location-context.js";
import {
  PlaceCandidateProvider,
  PlaceCandidateProviderError
} from "./place-candidate.provider.js";
import { PlaceCardPresenter } from "./place-card.presenter.js";
import { PlaceCategoryMapper } from "./place-category.mapper.js";
import { PlaceDiscoveryInput } from "./place-discovery.input.js";
import { distanceMeters } from "./place-distance.js";
import { PlaceRepository } from "./place.repository.js";
import {
  PlaceDomainError,
  type PlaceCard,
  type PlaceDiscoverOptions,
  type PlaceHeatLevel,
  type PlaceProjection,
  type RawPlaceCandidate,
  type PlaceSort
} from "./place.types.js";

const HEAT_RANK: Record<PlaceHeatLevel, number> = {
  quiet: 0,
  neutral: 1,
  active: 2,
  veryActive: 3,
  hot: 4
};

const PROVIDER_PHOTO_REFRESH_MS = 7 * 24 * 60 * 60 * 1000;

@Injectable()
export class PlaceService {
  constructor(
    private readonly repository: PlaceRepository,
    private readonly candidates: PlaceCandidateProvider,
    private readonly locations: LocationContextReader,
    private readonly categoryMapper: PlaceCategoryMapper,
    private readonly inputParser: PlaceDiscoveryInput,
    private readonly cardPresenter: PlaceCardPresenter
  ) {}

  async discover(input: {
    userId: string;
    locationContextToken: unknown;
    body: Record<string, unknown>;
    now?: Date;
  }): Promise<{ items: PlaceCard[]; nextCursor: string | null; hasMore: boolean }> {
    const now = input.now ?? new Date();
    const token = this.locationToken(input.locationContextToken);
    let location;
    try {
      location = await this.locations.resolve({
        token,
        userId: input.userId,
        now
      });
    } catch (error) {
      if (error instanceof LocationContextError) {
        throw new PlaceDomainError(error.code, error.message, error.status);
      }
      throw error;
    }
    const options = this.inputParser.parse({
      userId: input.userId,
      location,
      body: input.body
    });
    let measured = await this.loadMeasured(options);
    this.sort(measured, options.sort);

    const visibleWindow = measured.slice(
      options.offset,
      options.offset + options.limit + 1
    );
    const needsMoreCandidates =
      measured.length < options.offset + options.limit + 1;
    const needsPhotoRefresh = visibleWindow.some(({ projection }) => {
      const checkedAt = projection.providerPhotoCheckedAt;
      return (
        checkedAt === null ||
        now.getTime() - checkedAt.getTime() >= PROVIDER_PHOTO_REFRESH_MS
      );
    });

    if (!options.historyOnly && (needsMoreCandidates || needsPhotoRefresh)) {
      let rawCandidates: RawPlaceCandidate[] = [];
      let providerSucceeded = false;
      try {
        rawCandidates = await this.candidates.discover({
          location,
          radiusMeters: options.distanceMeters,
          keyword: options.keyword,
          categoryKeys: options.categoryKeys,
          limit: needsPhotoRefresh
            ? 50
            : Math.min(50, options.offset + options.limit + 1)
        });
        providerSucceeded = true;
      } catch (error) {
        if (!(error instanceof PlaceCandidateProviderError)) throw error;
      }
      if (providerSucceeded && needsPhotoRefresh) {
        await this.repository.markProviderPhotosChecked({
          placeGroupIds: visibleWindow.map(
            ({ projection }) => projection.placeGroupId
          ),
          checkedAt: now
        });
      }
      if (rawCandidates.length > 0) {
        await this.repository.activateCandidates(
          rawCandidates.map((candidate) => ({
            ...candidate,
            categoryKey: this.categoryMapper.map(candidate)
          }))
        );
        measured = await this.loadMeasured(options);
        this.sort(measured, options.sort);
      }
    }

    const page = measured.slice(options.offset, options.offset + options.limit + 1);
    const hasMore = page.length > options.limit;
    const items = page
      .slice(0, options.limit)
      .map(({ projection, meters }) => this.cardPresenter.present(projection, meters));
    return {
      items,
      nextCursor: hasMore
        ? this.inputParser.encodeCursor(options.offset + items.length)
        : null,
      hasMore
    };
  }

  private async loadMeasured(
    options: PlaceDiscoverOptions
  ): Promise<Array<{ projection: PlaceProjection; meters: number }>> {
    const projections = await this.repository.findActiveAround({
      userId: options.userId,
      query: options
    });
    return projections
      .map((projection) => ({
        projection,
        meters: distanceMeters(options.location, {
          coordinateSystem: "gcj02",
          longitude: projection.longitude,
          latitude: projection.latitude
        })
      }))
      .filter(({ meters }) => meters <= options.distanceMeters);
  }

  private sort(
    items: Array<{ projection: PlaceProjection; meters: number }>,
    sort: PlaceSort
  ): void {
    items.sort((a, b) => {
      if (sort === "distance") return a.meters - b.meters;
      const heatDelta =
        HEAT_RANK[b.projection.heatLevel] - HEAT_RANK[a.projection.heatLevel];
      return heatDelta || a.meters - b.meters;
    });
  }

  private locationToken(value: unknown): string {
    if (typeof value !== "string" || !value.trim()) {
      throw new PlaceDomainError(
        "LOCATION_CONTEXT_REQUIRED",
        "请刷新定位后重试",
        400
      );
    }
    return value.trim();
  }
}
