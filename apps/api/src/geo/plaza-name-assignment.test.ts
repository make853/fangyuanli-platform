import assert from "node:assert/strict";
import test from "node:test";
import { assignPlazaNames } from "./plaza-name-assignment.js";
import type { PlazaNameCandidate } from "./plaza-naming.provider.js";

const candidate = (
  name: string,
  score: number,
  kind: PlazaNameCandidate["kind"] = "public_square"
): PlazaNameCandidate => ({
  name,
  score,
  kind,
  source: kind === "community" ? "community" : "venue"
});

test("joint assignment gives a shared landmark to the grid that needs it most", () => {
  const assigned = assignPlazaNames([
    {
      plazaId: "west",
      candidates: [candidate("民权站广场", 1000), candidate("中央城市广场", 980)]
    },
    {
      plazaId: "east",
      candidates: [
        candidate("民权站广场", 990),
        candidate("南华社区广场", 300, "community")
      ]
    }
  ]);

  assert.equal(assigned.get("west")?.name, "中央城市广场");
  assert.equal(assigned.get("east")?.name, "民权站广场");
});

test("never reuses a reserved or already assigned plaza name", () => {
  const assigned = assignPlazaNames(
    [
      {
        plazaId: "one",
        candidates: [candidate("民权站广场", 1000), candidate("逍遥苑广场", 900)]
      },
      {
        plazaId: "two",
        candidates: [candidate("逍遥苑广场", 950), candidate("绿洲社区广场", 800, "community")]
      }
    ],
    new Set(["民权站广场"])
  );

  assert.equal(assigned.get("one")?.name, "逍遥苑广场");
  assert.equal(assigned.get("two")?.name, "绿洲社区广场");
});
