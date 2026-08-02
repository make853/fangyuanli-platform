import assert from "node:assert/strict";
import test from "node:test";
import type { QueryResult, QueryResultRow } from "pg";
import type { QueryExecutor } from "../database/database.types.js";
import { LocationContextReader } from "../geo/location-context.js";
import { ConversationAccessService } from "./conversation-access.service.js";
import { ConversationDomainError } from "./conversation.types.js";

const userId = "019f0000-0000-7000-8000-00000000000a";
const conversationId = "019f0000-0000-7000-8000-00000000000c";
const plazaIds = [
  "019f0000-0000-7000-8000-000000000101",
  "019f0000-0000-7000-8000-000000000102",
  "019f0000-0000-7000-8000-000000000103",
  "019f0000-0000-7000-8000-000000000104"
];

function result<R extends QueryResultRow>(rows: R[]): QueryResult<R> {
  return {
    command: "SELECT",
    rowCount: rows.length,
    oid: 0,
    fields: [],
    rows
  };
}

function plazaExecutor(input: {
  currentEligible: boolean;
  hasHistory: boolean;
}): QueryExecutor {
  return {
    async query<R extends QueryResultRow>(text: string): Promise<QueryResult<R>> {
      if (text.includes("FROM conversations")) {
        return result([
          {
            id: conversationId,
            type: "plaza",
            latest_sequence: 9,
            status: "active"
          }
        ] as R[]);
      }
      if (text.includes("FROM plaza_grids grid")) {
        return result([
          {
            plaza_id: plazaIds[0],
            current_eligible: input.currentEligible,
            has_history: input.hasHistory,
            notification_mode: "normal"
          }
        ] as R[]);
      }
      throw new Error(`Unexpected query: ${text}`);
    }
  };
}

function readerAndToken(authorizedPlazaIds = plazaIds): {
  reader: LocationContextReader;
  token: string;
} {
  const reader = LocationContextReader.withKeyForTesting(Buffer.alloc(32, 6));
  const now = new Date();
  return {
    reader,
    token: reader.issue({
      userId,
      snapshot: {
        coordinateSystem: "gcj02",
        longitude: 115.14,
        latitude: 34.65,
        accuracyMeters: 15,
        capturedAt: now,
        expiresAt: new Date(now.getTime() + 60_000),
        authorizedPlazaIds
      }
    })
  };
}

test("allows a current four-plaza member to send with a matching location context", async () => {
  const { reader, token } = readerAndToken();
  const service = new ConversationAccessService(reader);

  const access = await service.authorize(
    plazaExecutor({ currentEligible: true, hasHistory: false }),
    {
      userId,
      conversationId,
      capability: "send",
      locationContextToken: token
    }
  );

  assert.equal(access.type, "plaza");
  assert.equal(access.currentRole, "nearby");
  assert.equal(access.canSendMessage, true);
  assert.equal(access.navigationKey, "plaza");
});

test("keeps historical plaza messages viewable but does not permit remote sending", async () => {
  const { reader, token } = readerAndToken();
  const service = new ConversationAccessService(reader);
  const executor = plazaExecutor({ currentEligible: false, hasHistory: true });

  const access = await service.authorize(executor, {
    userId,
    conversationId,
    capability: "view"
  });
  assert.equal(access.currentRole, "history");
  assert.equal(access.canViewHistory, true);

  await assert.rejects(
    service.authorize(executor, {
      userId,
      conversationId,
      capability: "send",
      locationContextToken: token
    }),
    (error: unknown) =>
      error instanceof ConversationDomainError &&
      error.code === "PLAZA_LOCATION_CONTEXT_REQUIRED"
  );
});

test("rejects a valid location context issued for a different four-plaza set", async () => {
  const { reader, token } = readerAndToken([
    "019f0000-0000-7000-8000-000000000201",
    "019f0000-0000-7000-8000-000000000202",
    "019f0000-0000-7000-8000-000000000203",
    "019f0000-0000-7000-8000-000000000204"
  ]);
  const service = new ConversationAccessService(reader);

  await assert.rejects(
    service.authorize(
      plazaExecutor({ currentEligible: true, hasHistory: false }),
      {
        userId,
        conversationId,
        capability: "send",
        locationContextToken: token
      }
    ),
    (error: unknown) =>
      error instanceof ConversationDomainError &&
      error.code === "PLAZA_LOCATION_NOT_AUTHORIZED"
  );
});
