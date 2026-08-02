import assert from "node:assert/strict";
import test from "node:test";
import type { DatabaseService } from "../database/database.service.js";
import type { QueryExecutor } from "../database/database.types.js";
import { PlazaContextRepository } from "./plaza-context.repository.js";
import { PlazaGridProjector } from "./plaza-grid-projector.js";
import type { PlazaGridVersion } from "./plaza-context.types.js";

const version: PlazaGridVersion = {
  id: "019f0b00-0000-7000-8000-000000000001",
  version: 1,
  coordinateSystem: "gcj02",
  projectionKey: "gcj02-web-mercator-v1",
  sideLengthMeters: 500
};

class FakeDatabase {
  statements: string[] = [];
  cells = new Set<string>();

  async transaction<T>(work: (executor: QueryExecutor) => Promise<T>): Promise<T> {
    return work({ query: this.query.bind(this) });
  }

  async query<R extends Record<string, unknown>>(
    sql: string,
    values: unknown[] = []
  ): Promise<{ rows: R[]; rowCount: number }> {
    const normalized = sql.replace(/\s+/g, " ").trim();
    this.statements.push(normalized);
    if (normalized.startsWith("SELECT 1 FROM plaza_grids")) {
      const key = `${values[1]}:${values[2]}`;
      const rows = this.cells.has(key) ? ([{}] as R[]) : [];
      return { rows, rowCount: rows.length };
    }
    if (normalized.startsWith("INSERT INTO plaza_grids")) {
      this.cells.add(`${values[2]}:${values[3]}`);
      return { rows: [], rowCount: 1 };
    }
    if (normalized.startsWith("SELECT grid.id AS plaza_id")) {
      const coordinates = values[2] as string[];
      const rows = coordinates.map((coordinate, index) => {
        const [gridX, gridY] = coordinate.split(":");
        return {
          plaza_id: `019f0b00-0000-7000-8000-00000000001${index}`,
          conversation_id: `019f0b00-0000-7000-8000-00000000002${index}`,
          display_name: `区域广场 ${index}`,
          grid_x: gridX,
          grid_y: gridY,
          latest_sequence: "0",
          last_read_sequence: "0",
          notification_mode: "normal"
        } as R;
      });
      return { rows, rowCount: rows.length };
    }
    if (normalized.startsWith("WITH claimable AS")) {
      const coordinates = values[1] as string[];
      const rows = coordinates.map((coordinate, index) => {
        const [gridX, gridY] = coordinate.split(":");
        return {
          plaza_id: `019f0b00-0000-7000-8000-00000000003${index}`,
          grid_x: gridX,
          grid_y: gridY
        } as R;
      });
      return { rows, rowCount: rows.length };
    }
    return { rows: [], rowCount: 0 };
  }
}

test("lazily creates one plaza conversation per stable grid cell", async () => {
  const database = new FakeDatabase();
  const repository = new PlazaContextRepository(
    database as unknown as DatabaseService,
    new PlazaGridProjector()
  );
  const cells = [
    { gridX: 1, gridY: 1 },
    { gridX: 2, gridY: 1 },
    { gridX: 1, gridY: 2 },
    { gridX: 2, gridY: 2 }
  ];

  const first = await repository.ensurePlazas({ userId: "user-1", version, cells });
  const second = await repository.ensurePlazas({ userId: "user-1", version, cells });

  assert.equal(first.length, 4);
  assert.equal(second.length, 4);
  assert.equal(
    database.statements.filter((sql) => sql.startsWith("INSERT INTO conversations"))
      .length,
    4
  );
  assert.equal(
    database.statements.filter((sql) => sql.startsWith("INSERT INTO plaza_grids")).length,
    4
  );
  assert.equal(
    database.statements.filter((sql) => sql.includes("pg_advisory_xact_lock")).length,
    8
  );
});

test("serializes anchor updates per user through a transaction lock", async () => {
  const database = new FakeDatabase();
  const repository = new PlazaContextRepository(
    database as unknown as DatabaseService,
    new PlazaGridProjector()
  );

  const result = await repository.serializeForUser("user-1", async () => "done");

  assert.equal(result, "done");
  assert.equal(
    database.statements.some(
      (sql) => sql.includes("pg_advisory_xact_lock") && sql.includes("hashtextextended")
    ),
    true
  );
});

test("atomically claims neutral plazas before external naming lookups", async () => {
  const database = new FakeDatabase();
  const repository = new PlazaContextRepository(
    database as unknown as DatabaseService,
    new PlazaGridProjector()
  );

  const claimed = await repository.claimNeutralPlazasByCells({
    version,
    cells: [
      { gridX: 1, gridY: 2 },
      { gridX: 2, gridY: 2 }
    ]
  });

  assert.deepEqual(
    claimed.map(({ gridX, gridY }) => ({ gridX, gridY })),
    [
      { gridX: 1, gridY: 2 },
      { gridX: 2, gridY: 2 }
    ]
  );
  const claimSql = database.statements.find((sql) => sql.startsWith("WITH claimable AS"));
  assert.match(claimSql ?? "", /FOR UPDATE SKIP LOCKED/);
  assert.match(claimSql ?? "", /naming_retry_after/);
});
