import assert from "node:assert/strict";
import test from "node:test";
import { PlazaAnchorPolicy } from "./plaza-anchor-policy.js";
import { PlazaGridProjector } from "./plaza-grid-projector.js";
import type { PlazaAnchor } from "./plaza-context.types.js";
import type { PlazaPolicyValues } from "./plaza-policy.js";

const userId = "019f0000-0000-7000-8000-00000000000a";
const now = new Date("2026-08-02T10:00:00.000Z");
const policy: PlazaPolicyValues = {
  version: 2,
  anchorRadiusMeters: 150,
  maximumAccuracyMeters: 80,
  locationContextTtlMilliseconds: 600_000
};

function anchor(overrides: Partial<PlazaAnchor> = {}): PlazaAnchor {
  return {
    userId,
    gridVersionId: "grid-version-1",
    point: {
      coordinateSystem: "gcj02",
      longitude: 121.4737,
      latitude: 31.2304
    },
    plazaIds: ["old-main", "old-a", "old-b", "old-c"],
    pendingPlazaIds: null,
    pendingConfirmationCount: 0,
    pendingFirstSeenAt: null,
    lastAccuracyMeters: 10,
    anchorPolicyVersion: 2,
    createdAt: new Date("2026-08-02T09:00:00.000Z"),
    lastConfirmedAt: new Date("2026-08-02T09:59:00.000Z"),
    updatedAt: new Date("2026-08-02T09:59:00.000Z"),
    ...overrides
  };
}

function decide(existing: PlazaAnchor, at: Date) {
  return new PlazaAnchorPolicy(new PlazaGridProjector()).decide({
    userId,
    gridVersionId: "grid-version-1",
    point: {
      coordinateSystem: "gcj02",
      longitude: 121.4755,
      latitude: 31.2304
    },
    accuracyMeters: 15,
    candidatePlazaIds: ["new-main", "new-a", "new-b", "new-c"],
    existing,
    now: at,
    policy
  });
}

test("keeps the existing four plazas inside the 150 metre anchor", () => {
  const existing = anchor();
  const decision = new PlazaAnchorPolicy(new PlazaGridProjector()).decide({
    userId,
    gridVersionId: "grid-version-1",
    point: {
      coordinateSystem: "gcj02",
      longitude: 121.474,
      latitude: 31.2304
    },
    accuracyMeters: 12,
    candidatePlazaIds: ["new-main", "new-a", "new-b", "new-c"],
    existing,
    now,
    policy
  });

  assert.deepEqual(decision.plazaIds, existing.plazaIds);
  assert.equal(decision.isReused, true);
  assert.equal(decision.recalculationPending, false);
});

test("switches on the first accurate sample outside the anchor", () => {
  const decision = decide(anchor(), now);

  assert.equal(decision.recalculationPending, false);
  assert.equal(decision.isReused, false);
  assert.deepEqual(decision.plazaIds, ["new-main", "new-a", "new-b", "new-c"]);
  assert.deepEqual(decision.anchor.point, {
    coordinateSystem: "gcj02",
    longitude: 121.4755,
    latitude: 31.2304
  });
  assert.equal(decision.anchor.pendingPlazaIds, null);
  assert.equal(decision.anchor.pendingConfirmationCount, 0);
  assert.equal(decision.anchor.pendingFirstSeenAt, null);
});

test("clears obsolete pending confirmation state while switching", () => {
  const existing = anchor({
    pendingPlazaIds: ["other-main", "other-a", "other-b", "other-c"],
    pendingConfirmationCount: 2,
    pendingFirstSeenAt: new Date(now.getTime() - 120_000)
  });
  const decision = decide(existing, now);

  assert.equal(decision.recalculationPending, false);
  assert.equal(decision.anchor.pendingPlazaIds, null);
  assert.equal(decision.anchor.pendingConfirmationCount, 0);
  assert.equal(decision.anchor.pendingFirstSeenAt, null);
});
