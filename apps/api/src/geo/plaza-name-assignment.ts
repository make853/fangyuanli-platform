import type {
  PlazaNameCandidate,
  PlazaNamingKind
} from "./plaza-naming.provider.js";

export type PlazaCandidateSet = {
  plazaId: string;
  candidates: PlazaNameCandidate[];
};

const MAX_CANDIDATES_PER_PLAZA = 12;
const NEW_KIND_BONUS = 45;

/**
 * Finds the best assignment for the visible four-plaza group as a whole.
 *
 * A greedy per-plaza choice can consume a shared landmark even when another
 * grid has no comparable alternative. Four plazas are small enough for a
 * bounded exhaustive search, which keeps the policy deterministic and easy to
 * test while maximizing total semantic and distance score.
 */
export function assignPlazaNames(
  sets: PlazaCandidateSet[],
  reservedNames: ReadonlySet<string> = new Set()
): Map<string, PlazaNameCandidate> {
  const pools = sets.map((set) => ({
    plazaId: set.plazaId,
    candidates: set.candidates
      .filter((candidate) => !reservedNames.has(candidate.name))
      .slice(0, MAX_CANDIDATES_PER_PLAZA)
  }));
  const usedNames = new Set(reservedNames);
  const kindCounts = new Map<PlazaNamingKind, number>();
  const current = new Map<string, PlazaNameCandidate>();
  let best = new Map<string, PlazaNameCandidate>();
  let bestScore = Number.NEGATIVE_INFINITY;
  let bestKey = "";

  const visit = (index: number, score: number): void => {
    if (index === pools.length) {
      const key = pools
        .map(({ plazaId }) => current.get(plazaId)?.name ?? "~")
        .join("|");
      if (score > bestScore || (score === bestScore && (!bestKey || key < bestKey))) {
        bestScore = score;
        bestKey = key;
        best = new Map(current);
      }
      return;
    }

    const pool = pools[index]!;
    for (const candidate of pool.candidates) {
      if (usedNames.has(candidate.name)) continue;
      const existingKindCount = kindCounts.get(candidate.kind) ?? 0;
      usedNames.add(candidate.name);
      kindCounts.set(candidate.kind, existingKindCount + 1);
      current.set(pool.plazaId, candidate);
      visit(
        index + 1,
        score + candidate.score + (existingKindCount === 0 ? NEW_KIND_BONUS : 0)
      );
      current.delete(pool.plazaId);
      if (existingKindCount === 0) kindCounts.delete(candidate.kind);
      else kindCounts.set(candidate.kind, existingKindCount);
      usedNames.delete(candidate.name);
    }

    // A grid can remain on its existing name when every candidate conflicts or
    // is worse than preserving the current assignment.
    visit(index + 1, score);
  };

  visit(0, 0);
  return best;
}
