import { Injectable } from "@nestjs/common";
import { PlazaContextRepository } from "./plaza-context.repository.js";
import type {
  PlazaCell,
  PlazaGridVersion,
  PlazaProjection
} from "./plaza-context.types.js";
import { PlazaGridProjector } from "./plaza-grid-projector.js";
import { assignPlazaNames } from "./plaza-name-assignment.js";
import {
  PLAZA_NAMING_POLICY_VERSION,
  PlazaNamingProvider
} from "./plaza-naming.provider.js";

@Injectable()
export class PlazaNamingService {
  constructor(
    private readonly provider: PlazaNamingProvider,
    private readonly repository: PlazaContextRepository,
    private readonly projector: PlazaGridProjector
  ) {}

  /**
   * Best-effort enrichment. Map outages must never prevent a user from entering
   * nearby plazas, and a stable name never changes the plaza or conversation ID.
   */
  async enrich(input: {
    version: PlazaGridVersion;
    cells: PlazaCell[];
    plazas: PlazaProjection[];
  }): Promise<boolean> {
    if (!this.provider.isConfigured()) return false;
    const claimable = await this.repository.claimPlazasForNamingByCells({
      ...input,
      policyVersion: PLAZA_NAMING_POLICY_VERSION
    });
    if (claimable.length === 0) return false;

    const claimableIds = new Set(claimable.map((plaza) => plaza.plazaId));
    const usedNames = new Set(
      input.plazas
        .filter((plaza) => !claimableIds.has(plaza.plazaId))
        .map((plaza) => plaza.name)
    );
    const lookups = await Promise.all(
      claimable.map(async (plaza) => {
        try {
          const discovered = await this.provider.candidates(
            this.projector.center(plaza, input.version)
          );
          // Discovery may intentionally search beyond the region so that the
          // map provider returns enough high-quality POIs. Assignment is much
          // stricter: an auditable coordinate must be covered by this cell.
          const candidates = discovered.filter(
            (candidate) =>
              candidate.point !== undefined &&
              this.projector.contains(plaza, input.version, candidate.point)
          );
          return { plaza, candidates, failed: false };
        } catch {
          await this.repository.deferPlazaNaming({
            plazaId: plaza.plazaId,
            retryAfter: new Date(Date.now() + 30 * 60 * 1000),
            policyVersion: PLAZA_NAMING_POLICY_VERSION
          });
          return { plaza, candidates: [], failed: true };
        }
      })
    );

    let changed = false;
    const assignments = assignPlazaNames(
      lookups
        .filter((lookup) => !lookup.failed)
        .map((lookup) => ({
          plazaId: lookup.plaza.plazaId,
          candidates: lookup.candidates
        })),
      usedNames
    );
    for (const lookup of lookups) {
      if (lookup.failed) continue;
      const candidate = assignments.get(lookup.plaza.plazaId);
      if (!candidate?.point) {
        const reset = await this.repository.applyNeutralPlazaName({
          plazaId: lookup.plaza.plazaId,
          version: input.version,
          cell: lookup.plaza,
          retryAfter: new Date(Date.now() + 6 * 60 * 60 * 1000),
          policyVersion: PLAZA_NAMING_POLICY_VERSION
        });
        if (reset) changed = true;
        continue;
      }
      const updated = await this.repository.applyPlazaNameCandidate({
        plazaId: lookup.plaza.plazaId,
        name: candidate.name,
        source: candidate.source,
        kind: candidate.kind,
        point: candidate.point,
        provider: candidate.provider ?? null,
        providerPlaceId: candidate.providerPlaceId ?? null,
        policyVersion: PLAZA_NAMING_POLICY_VERSION
      });
      if (updated) {
        usedNames.add(candidate.name);
        changed = true;
      }
    }
    return changed;
  }
}
