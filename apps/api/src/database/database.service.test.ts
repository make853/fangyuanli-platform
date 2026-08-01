import assert from "node:assert/strict";
import test from "node:test";
import type { Pool, QueryResult, QueryResultRow } from "pg";
import { DatabaseService } from "./database.service.js";

function emptyResult<R extends QueryResultRow>(): QueryResult<R> {
  return {
    command: "",
    rowCount: 0,
    oid: 0,
    rows: [],
    fields: []
  };
}

class FakeClient {
  readonly statements: string[] = [];
  released = false;

  async query<R extends QueryResultRow = QueryResultRow>(
    text: string
  ): Promise<QueryResult<R>> {
    this.statements.push(text);
    return emptyResult<R>();
  }

  release(): void {
    this.released = true;
  }
}

class FakePool {
  readonly statements: string[] = [];
  readonly clients: FakeClient[] = [];
  ended = false;

  async query<R extends QueryResultRow = QueryResultRow>(
    text: string
  ): Promise<QueryResult<R>> {
    this.statements.push(text);
    return emptyResult<R>();
  }

  async connect(): Promise<FakeClient> {
    const client = new FakeClient();
    this.clients.push(client);
    return client;
  }

  async end(): Promise<void> {
    this.ended = true;
  }
}

function serviceWith(pool: FakePool): DatabaseService {
  return new DatabaseService(pool as unknown as Pool);
}

test("routes ordinary queries through the shared pool", async () => {
  const pool = new FakePool();
  const database = serviceWith(pool);

  await database.query("SELECT 1");

  assert.deepEqual(pool.statements, ["SELECT 1"]);
  assert.equal(pool.clients.length, 0);
});

test("commits successful work and releases the client", async () => {
  const pool = new FakePool();
  const database = serviceWith(pool);

  const value = await database.transaction(async (transaction) => {
    await transaction.query("INSERT INTO example VALUES (1)");
    return "committed";
  });

  assert.equal(value, "committed");
  assert.deepEqual(pool.clients[0]?.statements, [
    "BEGIN",
    "INSERT INTO example VALUES (1)",
    "COMMIT"
  ]);
  assert.equal(pool.clients[0]?.released, true);
});

test("rolls back failed work and releases the client", async () => {
  const pool = new FakePool();
  const database = serviceWith(pool);

  await assert.rejects(
    database.transaction(async (transaction) => {
      await transaction.query("INSERT INTO example VALUES (1)");
      throw new Error("stop");
    }),
    /stop/
  );

  assert.deepEqual(pool.clients[0]?.statements, [
    "BEGIN",
    "INSERT INTO example VALUES (1)",
    "ROLLBACK"
  ]);
  assert.equal(pool.clients[0]?.released, true);
});

test("nested work shares the ambient transaction", async () => {
  const pool = new FakePool();
  const database = serviceWith(pool);

  await database.transaction(async () => {
    await database.query("SELECT 'outer'");
    await database.transaction(async () => {
      await database.query("SELECT 'inner'");
    });
  });

  assert.equal(pool.clients.length, 1);
  assert.deepEqual(pool.clients[0]?.statements, [
    "BEGIN",
    "SELECT 'outer'",
    "SELECT 'inner'",
    "COMMIT"
  ]);
  assert.deepEqual(pool.statements, []);
});

test("owns and closes the shared pool once", async () => {
  const pool = new FakePool();
  const database = serviceWith(pool);

  await database.onApplicationShutdown();

  assert.equal(pool.ended, true);
});
