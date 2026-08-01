import { Inject, Injectable, OnApplicationShutdown } from "@nestjs/common";
import { AsyncLocalStorage } from "node:async_hooks";
import type { Pool, PoolClient, QueryResult, QueryResultRow } from "pg";
import type { QueryExecutor } from "./database.types.js";

export const DATABASE_POOL = Symbol("DATABASE_POOL");

@Injectable()
export class DatabaseService implements QueryExecutor, OnApplicationShutdown {
  private readonly transactionContext = new AsyncLocalStorage<PoolClient>();

  constructor(@Inject(DATABASE_POOL) private readonly pool: Pool) {}

  query<R extends QueryResultRow = QueryResultRow>(
    text: string,
    values?: unknown[]
  ): Promise<QueryResult<R>> {
    const executor = this.transactionContext.getStore() ?? this.pool;
    return executor.query<R>(text, values);
  }

  async transaction<T>(work: (executor: QueryExecutor) => Promise<T>): Promise<T> {
    const existing = this.transactionContext.getStore();
    if (existing) {
      return work(existing);
    }

    const client = await this.pool.connect();
    try {
      await client.query("BEGIN");
      const result = await this.transactionContext.run(client, () => work(client));
      await client.query("COMMIT");
      return result;
    } catch (error) {
      await client.query("ROLLBACK");
      throw error;
    } finally {
      client.release();
    }
  }

  async onApplicationShutdown(): Promise<void> {
    await this.pool.end();
  }
}
