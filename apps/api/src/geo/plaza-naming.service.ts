import { Injectable } from "@nestjs/common";
import { PlazaContextRepository } from "./plaza-context.repository.js";
import type {
  PlazaCell,
  PlazaGridVersion,
  PlazaProjection
} from "./plaza-context.types.js";
import { PlazaGridProjector } from "./plaza-grid-projector.js";
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
          const candidates = await this.provider.candidates(
            this.projector.center(plaza, input.version)
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
    for (const lookup of lookups) {
      if (lookup.failed) continue;
      const candidate = lookup.candidates.find((item) => !usedNames.has(item.name));
      if (!candidate) {
        await this.repository.deferPlazaNaming({
          plazaId: lookup.plaza.plazaId,
          retryAfter: new Date(Date.now() + 6 * 60 * 60 * 1000),
          policyVersion: PLAZA_NAMING_POLICY_VERSION
        });
        continue;
      }
      const updated = await this.repository.applyPlazaNameCandidate({
        plazaId: lookup.plaza.plazaId,
        name: candidate.name,
        source: candidate.source,
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
