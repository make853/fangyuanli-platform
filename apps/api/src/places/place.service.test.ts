import assert from "node:assert/strict";
import test from "node:test";
import type {
  LocationSnapshot
} from "../geo/location-context.js";
import { LocationContextReader } from "../geo/location-context.js";
import {
  PlaceCandidateProviderError,
  type PlaceCandidateProvider
} from "./place-candidate.provider.js";
import { PlaceCardPresenter } from "./place-card.presenter.js";
import { PlaceCategoryMapper } from "./place-category.mapper.js";
import { PlaceDiscoveryInput } from "./place-discovery.input.js";
import type { PlaceRepository } from "./place.repository.js";
import { PlaceService } from "./place.service.js";
import {
  PlaceDomainError,
  type PlaceCandidate,
  type PlaceProjection,
  type RawPlaceCandidate
} from "./place.types.js";

const userId = "019f0000-0000-7000-8000-00000000000a";
const location: LocationSnapshot = {
  coordinateSystem: "gcj02",
  longitude: 113.264385,
  latitude: 23.129112,
  accuracyMeters: 12,
  capturedAt: new Date("2026-08-02T08:00:00.000Z"),
  expiresAt: new Date("2026-08-02T08:10:00.000Z")
};

function projection(
  id: string,
  overrides: Partial<PlaceProjection> = {}
): PlaceProjection {
  return {
    placeGroupId: id,
    conversationId: `conversation-${id}`,
    name: `地点${id}`,
    address: "测试路",
    categoryKey: "food_retail",
    categoryName: "餐饮与商铺",
    longitude: location.longitude + 0.001,
    latitude: location.latitude,
    certificationStatus: "unverified",
    heatLevel: "quiet",
    latestSequence: 0,
    lastReadSequence: 0,
    notificationMode: "normal",
    role: null,
    speakPolicy: "nearbyAndMembers",
    visibilityRadiusMeters: 500,
    version: 1,
    ...overrides
  };
}

class FakeLocationReader {
  calls = 0;
  async resolve(): Promise<LocationSnapshot> {
    this.calls += 1;
    return location;
  }
}

class FakeCandidateProvider {
  calls = 0;
  results: RawPlaceCandidate[] = [];
  error: Error | null = null;
  async discover(): Promise<RawPlaceCandidate[]> {
    this.calls += 1;
    if (this.error) throw this.error;
    return this.results;
  }
}

class FakePlaceRepository {
  calls = 0;
  active: PlaceProjection[] = [];
  afterActivation: PlaceProjection[] | null = null;
  activated: PlaceCandidate[] = [];

  async findActiveAround(): Promise<PlaceProjection[]> {
    this.calls += 1;
    return this.active;
  }

  async activateCandidates(candidates: PlaceCandidate[]): Promise<void> {
    this.activated.push(...candidates);
    if (this.afterActivation) this.active = this.afterActivation;
  }
}

function fixture(): {
  repository: FakePlaceRepository;
  provider: FakeCandidateProvider;
  service: PlaceService;
} {
  const repository = new FakePlaceRepository();
  const provider = new FakeCandidateProvider();
  const reader = new FakeLocationReader();
  return {
    repository,
    provider,
    service: new PlaceService(
      repository as unknown as PlaceRepository,
      provider as unknown as PlaceCandidateProvider,
      reader as unknown as LocationContextReader,
      new PlaceCategoryMapper(),
      new PlaceDiscoveryInput(),
      new PlaceCardPresenter()
    )
  };
}

test("returns active groups in heat-first recommended order without leaking coordinates", async () => {
  const { repository, provider, service } = fixture();
  repository.active = [
    projection("quiet", { heatLevel: "quiet", longitude: location.longitude + 0.001 }),
    projection("hot", {
      heatLevel: "hot",
      longitude: location.longitude + 0.002,
      latestSequence: 9,
      lastReadSequence: 4,
      notificationMode: "muted"
    })
  ];

  const result = await service.discover({
    userId,
    locationContextToken: "location-token",
    body: { limit: 1 },
    now: new Date("2026-08-02T08:01:00.000Z")
  });

  assert.equal(result.items[0]?.placeGroupId, "hot");
  assert.deepEqual(result.items[0]?.unread, {
    count: 5,
    appearance: "gray",
    firstUnreadSequence: 5
  });
  assert.equal(result.hasMore, true);
  assert.ok(result.nextCursor);
  assert.equal(provider.calls, 0);
  assert.equal("longitude" in (result.items[0] ?? {}), false);
  assert.equal("latitude" in (result.items[0] ?? {}), false);
});

test("refreshes candidates and re-queries persisted groups when local results are insufficient", async () => {
  const { repository, provider, service } = fixture();
  repository.active = [];
  repository.afterActivation = [projection("new-place")];
  provider.results = [
    {
      provider: "amap",
      providerPlaceId: "amap-1",
      name: "新地点",
      address: null,
      coordinateSystem: "gcj02",
      longitude: location.longitude + 0.001,
      latitude: location.latitude,
      rawCategoryCode: "050100",
      rawCategoryName: "中餐厅",
      sourceUpdatedAt: new Date("2026-08-02T08:00:00.000Z")
    }
  ];

  const result = await service.discover({
    userId,
    locationContextToken: "location-token",
    body: { limit: 20 }
  });

  assert.equal(provider.calls, 1);
  assert.equal(repository.activated.length, 1);
  assert.equal(repository.calls, 2);
  assert.equal(result.items[0]?.placeGroupId, "new-place");
});

test("does not call the map provider for history-only discovery", async () => {
  const { provider, service } = fixture();
  const result = await service.discover({
    userId,
    locationContextToken: "location-token",
    body: { filters: { historyOnly: true } }
  });
  assert.deepEqual(result.items, []);
  assert.equal(provider.calls, 0);
});

test("returns persisted places when Amap is temporarily unavailable", async () => {
  const { repository, provider, service } = fixture();
  repository.active = [projection("persisted")];
  provider.error = new PlaceCandidateProviderError("temporary failure");

  const result = await service.discover({
    userId,
    locationContextToken: "location-token",
    body: { limit: 20 }
  });

  assert.equal(provider.calls, 1);
  assert.equal(result.items[0]?.placeGroupId, "persisted");
});

test("rejects invalid filters before touching place storage", async () => {
  const { repository, service } = fixture();
  await assert.rejects(
    service.discover({
      userId,
      locationContextToken: "location-token",
      body: { filters: { distanceMeters: 50 } }
    }),
    (error: unknown) =>
      error instanceof PlaceDomainError && error.code === "PLACE_DISTANCE_INVALID"
  );
  assert.equal(repository.calls, 0);
});
