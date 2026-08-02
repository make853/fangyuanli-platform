import { Injectable } from "@nestjs/common";
import type { Gcj02Point } from "./location-context.js";
import { PlazaGridProjector } from "./plaza-grid-projector.js";
import type { PlazaAnchor } from "./plaza-context.types.js";
import type { PlazaPolicyValues } from "./plaza-policy.js";

export type PlazaAnchorDecision = {
  plazaIds: string[];
  anchor: PlazaAnchor;
  isReused: boolean;
  recalculationPending: boolean;
};

@Injectable()
export class PlazaAnchorPolicy {
  constructor(private readonly projector: PlazaGridProjector) {}

  decide(input: {
    userId: string;
    gridVersionId: string;
    point: Gcj02Point;
    accuracyMeters: number;
    candidatePlazaIds: string[];
    existing: PlazaAnchor | null;
    now: Date;
    policy: PlazaPolicyValues;
  }): PlazaAnchorDecision {
    const { existing, candidatePlazaIds, now, policy } = input;
    if (!existing || existing.gridVersionId !== input.gridVersionId) {
      return this.accept(input, candidatePlazaIds, false);
    }

    const distance = this.projector.distanceMeters(existing.point, input.point);
    if (distance <= policy.anchorRadiusMeters) {
      return {
        plazaIds: [...existing.plazaIds],
        anchor: {
          ...existing,
          pendingPlazaIds: null,
          pendingConfirmationCount: 0,
          pendingFirstSeenAt: null,
          lastAccuracyMeters: input.accuracyMeters,
          lastConfirmedAt: now,
          updatedAt: now
        },
        isReused: true,
        recalculationPending: false
      };
    }

    if (this.sameCombination(existing.plazaIds, candidatePlazaIds)) {
      return this.accept(input, existing.plazaIds, true, existing.createdAt);
    }

    const isSamePending =
      existing.pendingPlazaIds !== null &&
      this.sameCombination(existing.pendingPlazaIds, candidatePlazaIds);
    const pendingFirstSeenAt = isSamePending
      ? (existing.pendingFirstSeenAt ?? now)
      : now;
    const pendingConfirmationCount = isSamePending
      ? existing.pendingConfirmationCount + 1
      : 1;
    const dwellMet =
      now.getTime() - pendingFirstSeenAt.getTime() >= policy.switchDwellMilliseconds;
    const confirmationsMet =
      pendingConfirmationCount >= policy.switchConfirmationCount;

    if (dwellMet && confirmationsMet) {
      return this.accept(input, candidatePlazaIds, false, existing.createdAt);
    }

    return {
      plazaIds: [...existing.plazaIds],
      anchor: {
        ...existing,
        pendingPlazaIds: [...candidatePlazaIds],
        pendingConfirmationCount,
        pendingFirstSeenAt,
        lastAccuracyMeters: input.accuracyMeters,
        updatedAt: now
      },
      isReused: true,
      recalculationPending: true
    };
  }

  private accept(
    input: {
      userId: string;
      gridVersionId: string;
      point: Gcj02Point;
      accuracyMeters: number;
      now: Date;
      policy: PlazaPolicyValues;
    },
    plazaIds: string[],
    isReused: boolean,
    createdAt = input.now
  ): PlazaAnchorDecision {
    return {
      plazaIds: [...plazaIds],
      anchor: {
        userId: input.userId,
        gridVersionId: input.gridVersionId,
        point: { ...input.point },
        plazaIds: [...plazaIds],
        pendingPlazaIds: null,
        pendingConfirmationCount: 0,
        pendingFirstSeenAt: null,
        lastAccuracyMeters: input.accuracyMeters,
        anchorPolicyVersion: input.policy.version,
        createdAt,
        lastConfirmedAt: input.now,
        updatedAt: input.now
      },
      isReused,
      recalculationPending: false
    };
  }

  private sameCombination(left: string[], right: string[]): boolean {
    if (left.length !== right.length || left[0] !== right[0]) return false;
    const leftAdjacent = left.slice(1).sort();
    const rightAdjacent = right.slice(1).sort();
    return leftAdjacent.every((value, index) => value === rightAdjacent[index]);
  }
}
