import assert from "node:assert/strict";
import test from "node:test";
import type { PlazaContextRepository } from "./plaza-context.repository.js";
import type { PlazaGridVersion, PlazaProjection } from "./plaza-context.types.js";
import { PlazaGridProjector } from "./plaza-grid-projector.js";
import type { PlazaNamingProvider } from "./plaza-naming.provider.js";
import { PLAZA_NAMING_POLICY_VERSION } from "./plaza-naming.provider.js";
import { PlazaNamingService } from "./plaza-naming.service.js";

const version: PlazaGridVersion = {
  id: "grid-v2",
  version: 2,
  coordinateSystem: "gcj02",
  projectionKey: "gcj02-web-mercator-v1",
  sideLengthMeters: 1000
};

const plazas: PlazaProjection[] = [0, 1].map((index) => ({
  plazaId: `plaza-${index}`,
  conversationId: `conversation-${index}`,
  name: `区域广场 ${index}`,
  gridX: index,
  gridY: 0,
  latestSequence: 0,
  lastReadSequence: 0,
  notificationMode: "normal"
}));

test("uses distinct stable candidates without changing plaza identity", async () => {
  const renamed: Array<{ plazaId: string; name: string }> = [];
  const repository = {
    claimPlazasForNamingByCells: async () =>
      plazas.map(({ plazaId, gridX, gridY }) => ({ plazaId, gridX, gridY })),
    applyPlazaNameCandidate: async (input: { plazaId: string; name: string }) => {
      renamed.push(input);
      return true;
    }
  } as unknown as PlazaContextRepository;
  const provider = {
    isConfigured: () => true,
    candidates: async (point: ReturnType<PlazaGridProjector["center"]>) => [
      {
        name: "滨江体育中心广场",
        source: "venue" as const,
        kind: "culture_scenic" as const,
        score: 1000,
        point,
        provider: "amap" as const,
        providerPlaceId: "venue-1"
      },
      {
        name: "滨江商圈广场",
        source: "landmark" as const,
        kind: "area" as const,
        score: 800,
        point,
        provider: "amap" as const,
        providerPlaceId: "area-1"
      }
    ]
  } as PlazaNamingProvider;
  const service = new PlazaNamingService(
    provider,
    repository,
    new PlazaGridProjector()
  );

  assert.equal(
    await service.enrich({
      version,
      cells: plazas.map(({ gridX, gridY }) => ({ gridX, gridY })),
      plazas
    }),
    true
  );
  assert.deepEqual(renamed, [
    {
      plazaId: "plaza-0",
      name: "滨江体育中心广场",
      source: "venue",
      kind: "culture_scenic",
      point: new PlazaGridProjector().center({ gridX: 0, gridY: 0 }, version),
      provider: "amap",
      providerPlaceId: "venue-1",
      policyVersion: PLAZA_NAMING_POLICY_VERSION
    },
    {
      plazaId: "plaza-1",
      name: "滨江商圈广场",
      source: "landmark",
      kind: "area",
      point: new PlazaGridProjector().center({ gridX: 1, gridY: 0 }, version),
      provider: "amap",
      providerPlaceId: "area-1",
      policyVersion: PLAZA_NAMING_POLICY_VERSION
    }
  ]);
});

test("map lookup failure never blocks plaza entry", async () => {
  const deferred: string[] = [];
  const repository = {
    claimPlazasForNamingByCells: async () => [
      { plazaId: "plaza-0", gridX: 0, gridY: 0 }
    ],
    deferPlazaNaming: async (input: { plazaId: string }) => {
      deferred.push(input.plazaId);
    },
    applyPlazaNameCandidate: async () => {
      throw new Error("must not rename");
    }
  } as unknown as PlazaContextRepository;
  const provider = {
    isConfigured: () => true,
    candidates: async () => {
      throw new Error("map unavailable");
    }
  } as PlazaNamingProvider;
  const service = new PlazaNamingService(
    provider,
    repository,
    new PlazaGridProjector()
  );

  assert.equal(
    await service.enrich({
      version,
      cells: [{ gridX: 0, gridY: 0 }],
      plazas: [plazas[0]!]
    }),
    false
  );
  assert.deepEqual(deferred, ["plaza-0"]);
});

test("does not claim naming work when the provider is not configured", async () => {
  let claimed = false;
  const repository = {
    claimPlazasForNamingByCells: async () => {
      claimed = true;
      return [];
    }
  } as unknown as PlazaContextRepository;
  const provider = {
    isConfigured: () => false,
    candidates: async () => {
      throw new Error("must not call map provider");
    }
  } as PlazaNamingProvider;
  const service = new PlazaNamingService(
    provider,
    repository,
    new PlazaGridProjector()
  );

  assert.equal(
    await service.enrich({
      version,
      cells: [{ gridX: 0, gridY: 0 }],
      plazas: [plazas[0]!]
    }),
    false
  );
  assert.equal(claimed, false);
});

test("never assigns a landmark outside the plaza cell", async () => {
  const renamed: string[] = [];
  const neutralized: string[] = [];
  const repository = {
    claimPlazasForNamingByCells: async () => [
      { plazaId: "plaza-0", gridX: 0, gridY: 0 }
    ],
    applyPlazaNameCandidate: async (input: { name: string }) => {
      renamed.push(input.name);
      return true;
    },
    applyNeutralPlazaName: async (input: { plazaId: string }) => {
      neutralized.push(input.plazaId);
      return true;
    }
  } as unknown as PlazaContextRepository;
  const projector = new PlazaGridProjector();
  const provider = {
    isConfigured: () => true,
    candidates: async () => [
      {
        name: "逍遥苑广场",
        source: "venue" as const,
        kind: "public_square" as const,
        score: 1800,
        point: projector.center({ gridX: 1, gridY: 0 }, version),
        provider: "amap" as const
      }
    ]
  } as PlazaNamingProvider;

  const changed = await new PlazaNamingService(
    provider,
    repository,
    projector
  ).enrich({
    version,
    cells: [{ gridX: 0, gridY: 0 }],
    plazas: [plazas[0]!]
  });

  assert.equal(changed, true);
  assert.deepEqual(renamed, []);
  assert.deepEqual(neutralized, ["plaza-0"]);
});

test("keeps only the inside candidate before joint assignment", async () => {
  const renamed: string[] = [];
  const repository = {
    claimPlazasForNamingByCells: async () => [
      { plazaId: "plaza-0", gridX: 0, gridY: 0 }
    ],
    applyPlazaNameCandidate: async (input: { name: string }) => {
      renamed.push(input.name);
      return true;
    }
  } as unknown as PlazaContextRepository;
  const projector = new PlazaGridProjector();
  const provider = {
    isConfigured: () => true,
    candidates: async () => [
      {
        name: "格外高分广场",
        source: "venue" as const,
        kind: "public_square" as const,
        score: 2000,
        point: projector.center({ gridX: 1, gridY: 0 }, version)
      },
      {
        name: "格内社区广场",
        source: "community" as const,
        kind: "community" as const,
        score: 900,
        point: projector.center({ gridX: 0, gridY: 0 }, version)
      }
    ]
  } as PlazaNamingProvider;

  await new PlazaNamingService(provider, repository, projector).enrich({
    version,
    cells: [{ gridX: 0, gridY: 0 }],
    plazas: [plazas[0]!]
  });

  assert.deepEqual(renamed, ["格内社区广场"]);
});
