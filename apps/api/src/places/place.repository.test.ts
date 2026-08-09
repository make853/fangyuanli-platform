import assert from "node:assert/strict";
import test from "node:test";
import type { DatabaseService } from "../database/database.service.js";
import type { QueryExecutor } from "../database/database.types.js";
import { PlaceRepository } from "./place.repository.js";
import type { PlaceCandidate } from "./place.types.js";

const candidate: PlaceCandidate = {
  provider: "amap",
  providerPlaceId: "amap-place-1",
  name: "隆江猪脚饭",
  address: "测试路1号",
  coordinateSystem: "gcj02",
  longitude: 113.264385,
  latitude: 23.129112,
  rawCategoryCode: "050100",
  rawCategoryName: "中餐厅",
  providerPhotoUrl: "https://images.example.test/store.jpg",
  providerPhotoTitle: "门店环境",
  categoryKey: "food_retail",
  sourceUpdatedAt: new Date("2026-08-02T08:00:00.000Z")
};

class FakeDatabase {
  statements: string[] = [];
  existingGroup = false;

  async query<R extends Record<string, unknown>>(
    sql: string
  ): Promise<{ rows: R[]; rowCount: number }> {
    this.statements.push(sql.replace(/\s+/g, " ").trim());
    return { rows: [], rowCount: 0 };
  }

  async transaction<T>(work: (executor: QueryExecutor) => Promise<T>): Promise<T> {
    return work({
      query: async <R extends Record<string, unknown>>(sql: string) => {
        this.statements.push(sql.replace(/\s+/g, " ").trim());
        if (sql.includes("RETURNING id")) {
          return { rows: [{ id: "poi-1" }], rowCount: 1 } as never;
        }
        if (sql.includes("SELECT 1 FROM place_groups")) {
          return {
            rows: this.existingGroup ? [{}] : [],
            rowCount: this.existingGroup ? 1 : 0
          } as never;
        }
        return { rows: [] as R[], rowCount: 0 } as never;
      }
    });
  }
}

test("serializes lazy activation and creates exactly one conversation per candidate", async () => {
  const database = new FakeDatabase();
  const repository = new PlaceRepository(database as unknown as DatabaseService);

  await repository.activateCandidates([candidate, candidate]);

  assert.equal(
    database.statements.filter((sql) => sql.includes("pg_advisory_xact_lock")).length,
    1
  );
  assert.equal(
    database.statements.filter((sql) => sql.startsWith("INSERT INTO conversations")).length,
    1
  );
  assert.equal(
    database.statements.filter((sql) => sql.startsWith("INSERT INTO place_groups")).length,
    1
  );
  assert.ok(
    database.statements.some(
      (sql) =>
        sql.includes("provider_photo_url") &&
        sql.includes("provider_photo_checked_at")
    )
  );
});

test("refreshes an existing POI without creating an orphan conversation", async () => {
  const database = new FakeDatabase();
  database.existingGroup = true;
  const repository = new PlaceRepository(database as unknown as DatabaseService);

  await repository.activateCandidates([candidate]);

  assert.equal(
    database.statements.some((sql) => sql.startsWith("INSERT INTO conversations")),
    false
  );
  assert.equal(
    database.statements.some((sql) => sql.startsWith("INSERT INTO place_groups")),
    false
  );
});

test("records a bounded provider photo refresh attempt for visible places", async () => {
  const database = new FakeDatabase();
  const repository = new PlaceRepository(database as unknown as DatabaseService);

  await repository.markProviderPhotosChecked({
    placeGroupIds: ["019f0000-0000-7000-8000-000000000001"],
    checkedAt: new Date("2026-08-10T00:00:00.000Z")
  });

  assert.ok(
    database.statements.some(
      (sql) =>
        sql.startsWith("UPDATE place_pois") &&
        sql.includes("provider_photo_checked_at")
    )
  );
});
