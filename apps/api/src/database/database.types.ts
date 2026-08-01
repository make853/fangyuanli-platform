import type { QueryResult, QueryResultRow } from "pg";

/**
 * Stable query boundary exposed to repositories.
 *
 * Feature modules depend on this interface instead of pg Pool/PoolClient so
 * the application can change its database implementation without leaking
 * connection lifecycle details across the codebase.
 */
export interface QueryExecutor {
  query<R extends QueryResultRow = QueryResultRow>(
    text: string,
    values?: unknown[]
  ): Promise<QueryResult<R>>;
}
