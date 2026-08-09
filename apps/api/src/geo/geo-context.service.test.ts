import assert from "node:assert/strict";
import test from "node:test";
import { GeoContextInput } from "./geo-context.input.js";
import { GeoContextService } from "./geo-context.service.js";
import { LocationContextReader } from "./location-context.js";
import { PlazaAnchorPolicy } from "./plaza-anchor-policy.js";
import type { PlazaContextRepository } from "./plaza-context.repository.js";
import { PlazaGridProjector } from "./plaza-grid-projector.js";
import type { PlazaNamingService } from "./plaza-naming.service.js";
import type {
  PlazaAnchor,
  PlazaGridVersion,
  PlazaProjection
} from "./plaza-context.types.js";
import { GeoDomainError } from "./plaza-context.types.js";
import { PlazaPolicy } from "./plaza-policy.js";

const userId = "019f0000-0000-7000-8000-00000000000a";
const now = new Date("2026-08-02T10:00:00.000Z");
const version: PlazaGridVersion = {
  id: "019f0b00-0000-7000-8000-000000000001",
  version: 1,
  coordinateSystem: "gcj02",
  projectionKey: "gcj02-web-mercator-v1",
  sideLengthMeters: 500
};

class FakeRepository {
  savedAnchor: PlazaAnchor | null = null;
  existingAnchor: PlazaAnchor | null = null;
  isSerializing = false;
  plazas: PlazaProjection[] = Array.from({ length: 4 }, (_, index) => ({
    plazaId: `019f0b00-0000-7000-8000-00000000001${index}`,
    conversationId: `019f0b00-0000-7000-8000-00000000002${index}`,
    name: `测试广场 ${index}`,
    gridX: index,
    gridY: 0,
    latestSequence: index === 0 ? 8 : 0,
    lastReadSequence: index === 0 ? 3 : 0,
    unreadCount: index === 0 ? 5 : 0,
    firstUnreadSequence: index === 0 ? 4 : null,
    notificationMode: index === 0 ? "muted" : "normal"
  }));

  async serializeForUser<T>(_userId: string, work: () => Promise<T>): Promise<T> {
    this.isSerializing = true;
    try {
      return await work();
    } finally {
      this.isSerializing = false;
    }
  }

  async activeGridVersion(): Promise<PlazaGridVersion> {
    return version;
  }

  async ensurePlazas(): Promise<PlazaProjection[]> {
    return this.plazas;
  }

  async findAnchor(): Promise<PlazaAnchor | null> {
    return this.existingAnchor;
  }

  async saveAnchor(anchor: PlazaAnchor): Promise<void> {
    this.savedAnchor = anchor;
  }

  async findPlazasByIds(): Promise<PlazaProjection[]> {
    return this.plazas;
  }
}

function fixture(
  environment: NodeJS.ProcessEnv = {},
  naming?: Pick<PlazaNamingService, "enrich">
): {
  repository: FakeRepository;
  service: GeoContextService;
} {
  const repository = new FakeRepository();
  const projector = new PlazaGridProjector();
  return {
    repository,
    service: new GeoContextService(
      new GeoContextInput(),
      repository as unknown as PlazaContextRepository,
      projector,
      new PlazaAnchorPolicy(projector),
      new PlazaPolicy(environment),
      LocationContextReader.withKeyForTesting(Buffer.alloc(32, 9)),
      (naming ?? {
        enrich: async () => {
          assert.equal(repository.isSerializing, false);
          return false;
        }
      }) as PlazaNamingService
    )
  };
}

function request(accuracyMeters = 18): Record<string, unknown> {
  return {
    coordinateSystem: "gcj02",
    longitude: 121.4737,
    latitude: 31.2304,
    accuracyMeters,
    capturedAt: "2026-08-02T09:59:30.000Z",
    motionState: "walking"
  };
}

test("issues an opaque context and exactly four privacy-safe plaza summaries", async () => {
  const { repository, service } = fixture();
  const result = await service.create({ userId, body: request(), now });

  assert.match(result.locationContextToken, /^loc1_/);
  assert.equal(result.plazas.length, 4);
  assert.equal(result.plazas[0]?.relation, "main");
  assert.equal(result.plazas.slice(1).every((plaza) => plaza.relation === "adjacent"), true);
  assert.equal(result.plazas[0]?.notificationMode, "muted");
  assert.equal(result.plazas[1]?.notificationMode, "normal");
  assert.deepEqual(result.plazas[0]?.unread, {
    count: 5,
    appearance: "gray",
    firstUnreadSequence: 4
  });
  assert.equal("longitude" in (result.plazas[0] ?? {}), false);
  assert.equal("latitude" in (result.plazas[0] ?? {}), false);
  assert.equal(repository.savedAnchor?.plazaIds.length, 4);
});

test("rejects poor accuracy before creating plazas or issuing a token", async () => {
  const { repository, service } = fixture({ PLAZA_MAXIMUM_ACCURACY_METERS: "50" });

  await assert.rejects(
    service.create({ userId, body: request(51), now }),
    (error: unknown) =>
      error instanceof GeoDomainError &&
      error.code === "GEO_CONTEXT_ACCURACY_INSUFFICIENT"
  );
  assert.equal(repository.savedAnchor, null);
});

test("returns the plaza context without waiting for external naming", async () => {
  let namingStarted = false;
  const { service } = fixture({}, {
    enrich: async () => {
      namingStarted = true;
      return new Promise<boolean>(() => undefined);
    }
  });

  const result = await Promise.race([
    service.create({ userId, body: request(), now }),
    new Promise<never>((_resolve, reject) =>
      setTimeout(() => reject(new Error("geo context waited for plaza naming")), 100)
    )
  ]);

  assert.equal(namingStarted, true);
  assert.equal(result.plazas.length, 4);
});
