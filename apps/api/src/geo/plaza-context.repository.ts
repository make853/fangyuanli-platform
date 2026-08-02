import { Injectable } from "@nestjs/common";
import { createHash, randomUUID } from "node:crypto";
import { DatabaseService } from "../database/database.service.js";
import type { QueryExecutor } from "../database/database.types.js";
import { PlazaGridProjector } from "./plaza-grid-projector.js";
import type {
  PlazaAnchor,
  PlazaCell,
  PlazaGridVersion,
  PlazaProjection
} from "./plaza-context.types.js";
import type { Gcj02Point } from "./location-context.js";
import type {
  PlazaNamingKind,
  PlazaNamingSource
} from "./plaza-naming.provider.js";

type GridVersionRow = {
  id: string;
  version: number;
  coordinate_system: "gcj02";
  projection_key: "gcj02-web-mercator-v1";
  side_length_meters: number;
};

type PlazaRow = {
  plaza_id: string;
  conversation_id: string;
  display_name: string;
  grid_x: string;
  grid_y: string;
  latest_sequence: string;
  last_read_sequence: string;
  unread_count: string;
  first_unread_sequence: string | null;
  notification_mode: "normal" | "muted";
};

type AnchorRow = {
  user_id: string;
  grid_version_id: string;
  anchor_longitude_gcj02: string;
  anchor_latitude_gcj02: string;
  plaza_ids: string[];
  pending_plaza_ids: string[] | null;
  pending_confirmation_count: number;
  pending_first_seen_at: Date | string | null;
  last_accuracy_meters: string;
  anchor_policy_version: number;
  created_at: Date | string;
  last_confirmed_at: Date | string;
  updated_at: Date | string;
};

@Injectable()
export class PlazaContextRepository {
  constructor(
    private readonly database: DatabaseService,
    private readonly projector: PlazaGridProjector
  ) {}

  async serializeForUser<T>(userId: string, work: () => Promise<T>): Promise<T> {
    return this.database.transaction(async (transaction) => {
      await transaction.query(
        "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))",
        [`plaza-anchor:${userId}`]
      );
      return work();
    });
  }

  async activeGridVersion(): Promise<PlazaGridVersion> {
    const result = await this.database.query<GridVersionRow>(
      `SELECT id, version, coordinate_system, projection_key, side_length_meters
         FROM plaza_grid_versions
        WHERE status = 'active'
        LIMIT 1`
    );
    const row = result.rows[0];
    if (!row) throw new Error("No active plaza grid version is configured");
    return {
      id: row.id,
      version: row.version,
      coordinateSystem: row.coordinate_system,
      projectionKey: row.projection_key,
      sideLengthMeters: row.side_length_meters
    };
  }

  async ensurePlazas(input: {
    userId: string;
    version: PlazaGridVersion;
    cells: PlazaCell[];
  }): Promise<PlazaProjection[]> {
    await this.database.transaction(async (transaction) => {
      for (const cell of input.cells) {
        await this.ensurePlaza(transaction, input.version, cell);
      }
    });
    return this.findPlazasByCells(input);
  }

  async findPlazasByIds(input: {
    userId: string;
    plazaIds: string[];
  }): Promise<PlazaProjection[]> {
    if (input.plazaIds.length === 0) return [];
    const result = await this.database.query<PlazaRow>(
      `${this.plazaSelect()}
        WHERE grid.id = ANY($2::uuid[])
          AND grid.status = 'active'`,
      [input.userId, input.plazaIds]
    );
    const byId = new Map(result.rows.map((row) => [row.plaza_id, this.projection(row)]));
    return input.plazaIds.flatMap((id) => {
      const plaza = byId.get(id);
      return plaza ? [plaza] : [];
    });
  }

  async findAnchor(userId: string): Promise<PlazaAnchor | null> {
    const result = await this.database.query<AnchorRow>(
      `SELECT user_id, grid_version_id, anchor_longitude_gcj02,
              anchor_latitude_gcj02, plaza_ids, pending_plaza_ids,
              pending_confirmation_count, pending_first_seen_at,
              last_accuracy_meters, anchor_policy_version, created_at,
              last_confirmed_at, updated_at
         FROM user_plaza_anchors
        WHERE user_id = $1`,
      [userId]
    );
    const row = result.rows[0];
    if (!row) return null;
    return {
      userId: row.user_id,
      gridVersionId: row.grid_version_id,
      point: {
        coordinateSystem: "gcj02",
        longitude: Number(row.anchor_longitude_gcj02),
        latitude: Number(row.anchor_latitude_gcj02)
      },
      plazaIds: row.plaza_ids,
      pendingPlazaIds: row.pending_plaza_ids,
      pendingConfirmationCount: row.pending_confirmation_count,
      pendingFirstSeenAt: this.dateOrNull(row.pending_first_seen_at),
      lastAccuracyMeters: Number(row.last_accuracy_meters),
      anchorPolicyVersion: row.anchor_policy_version,
      createdAt: new Date(row.created_at),
      lastConfirmedAt: new Date(row.last_confirmed_at),
      updatedAt: new Date(row.updated_at)
    };
  }

  async saveAnchor(anchor: PlazaAnchor): Promise<void> {
    await this.database.query(
      `INSERT INTO user_plaza_anchors (
         user_id, grid_version_id, anchor_longitude_gcj02,
         anchor_latitude_gcj02, plaza_ids, pending_plaza_ids,
         pending_confirmation_count, pending_first_seen_at,
         last_accuracy_meters, anchor_policy_version, created_at,
         last_confirmed_at, updated_at
       ) VALUES ($1, $2, $3, $4, $5::uuid[], $6::uuid[], $7, $8, $9, $10, $11, $12, $13)
       ON CONFLICT (user_id) DO UPDATE
         SET grid_version_id = EXCLUDED.grid_version_id,
             anchor_longitude_gcj02 = EXCLUDED.anchor_longitude_gcj02,
             anchor_latitude_gcj02 = EXCLUDED.anchor_latitude_gcj02,
             plaza_ids = EXCLUDED.plaza_ids,
             pending_plaza_ids = EXCLUDED.pending_plaza_ids,
             pending_confirmation_count = EXCLUDED.pending_confirmation_count,
             pending_first_seen_at = EXCLUDED.pending_first_seen_at,
             last_accuracy_meters = EXCLUDED.last_accuracy_meters,
             anchor_policy_version = EXCLUDED.anchor_policy_version,
             last_confirmed_at = EXCLUDED.last_confirmed_at,
             updated_at = EXCLUDED.updated_at`,
      [
        anchor.userId,
        anchor.gridVersionId,
        anchor.point.longitude,
        anchor.point.latitude,
        anchor.plazaIds,
        anchor.pendingPlazaIds,
        anchor.pendingConfirmationCount,
        anchor.pendingFirstSeenAt,
        anchor.lastAccuracyMeters,
        anchor.anchorPolicyVersion,
        anchor.createdAt,
        anchor.lastConfirmedAt,
        anchor.updatedAt
      ]
    );
  }

  private async findPlazasByCells(input: {
    userId: string;
    version: PlazaGridVersion;
    cells: PlazaCell[];
  }): Promise<PlazaProjection[]> {
    const coordinates = input.cells.map((cell) => `${cell.gridX}:${cell.gridY}`);
    const result = await this.database.query<PlazaRow>(
      `${this.plazaSelect()}
        WHERE grid.grid_version_id = $2
          AND concat(grid.grid_x, ':', grid.grid_y) = ANY($3::text[])
          AND grid.status = 'active'`,
      [input.userId, input.version.id, coordinates]
    );
    const byCell = new Map(
      result.rows.map((row) => [`${row.grid_x}:${row.grid_y}`, this.projection(row)])
    );
    return input.cells.flatMap((cell) => {
      const plaza = byCell.get(`${cell.gridX}:${cell.gridY}`);
      return plaza ? [plaza] : [];
    });
  }

  async claimPlazasForNamingByCells(input: {
    version: PlazaGridVersion;
    cells: PlazaCell[];
    policyVersion: number;
  }): Promise<Array<PlazaCell & { plazaId: string }>> {
    const coordinates = input.cells.map((cell) => `${cell.gridX}:${cell.gridY}`);
    const result = await this.database.query<{
      plaza_id: string;
      grid_x: string;
      grid_y: string;
    }>(
      `WITH claimable AS (
         SELECT id
           FROM plaza_grids
          WHERE grid_version_id = $1
            AND concat(grid_x, ':', grid_y) = ANY($2::text[])
            AND (naming_source = 'neutral' OR naming_policy_version < $3)
            AND status = 'active'
            AND (naming_retry_after IS NULL OR naming_retry_after <= now())
          FOR UPDATE SKIP LOCKED
       )
       UPDATE plaza_grids grid
          SET naming_last_attempted_at = now(),
              naming_retry_after = now() + interval '15 minutes'
         FROM claimable
        WHERE grid.id = claimable.id
      RETURNING grid.id AS plaza_id, grid.grid_x, grid.grid_y`,
      [input.version.id, coordinates, input.policyVersion]
    );
    return result.rows.map((row) => ({
      plazaId: row.plaza_id,
      gridX: Number(row.grid_x),
      gridY: Number(row.grid_y)
    }));
  }

  async applyPlazaNameCandidate(input: {
    plazaId: string;
    name: string;
    source: PlazaNamingSource;
    kind: PlazaNamingKind;
    point: Gcj02Point;
    provider: "amap" | null;
    providerPlaceId: string | null;
    policyVersion: number;
  }): Promise<boolean> {
    const result = await this.database.query(
      `UPDATE plaza_grids
          SET display_name = $2,
              naming_source = $3,
              naming_kind = $4,
              naming_provider = $5,
              naming_provider_place_id = $6,
              naming_longitude_gcj02 = $7,
              naming_latitude_gcj02 = $8,
              naming_policy_version = $9,
              naming_retry_after = NULL,
              updated_at = now()
        WHERE id = $1
          AND (naming_source = 'neutral' OR naming_policy_version < $9)
          AND status = 'active'`,
      [
        input.plazaId,
        input.name,
        input.source,
        input.kind,
        input.provider,
        input.providerPlaceId,
        input.point.longitude,
        input.point.latitude,
        input.policyVersion
      ]
    );
    return result.rowCount === 1;
  }

  async applyNeutralPlazaName(input: {
    plazaId: string;
    version: PlazaGridVersion;
    cell: PlazaCell;
    retryAfter: Date;
    policyVersion: number;
  }): Promise<boolean> {
    const result = await this.database.query(
      `UPDATE plaza_grids
          SET display_name = $2,
              naming_source = 'neutral',
              naming_kind = NULL,
              naming_provider = NULL,
              naming_provider_place_id = NULL,
              naming_longitude_gcj02 = NULL,
              naming_latitude_gcj02 = NULL,
              naming_policy_version = $3,
              naming_retry_after = $4,
              updated_at = now()
        WHERE id = $1
          AND (naming_source = 'neutral' OR naming_policy_version < $3)
          AND status = 'active'`,
      [
        input.plazaId,
        this.neutralName(input.version, input.cell),
        input.policyVersion,
        input.retryAfter
      ]
    );
    return result.rowCount === 1;
  }

  async deferPlazaNaming(input: {
    plazaId: string;
    retryAfter: Date;
    policyVersion: number;
  }): Promise<void> {
    await this.database.query(
      `UPDATE plaza_grids
          SET naming_retry_after = $2
        WHERE id = $1
          AND (naming_source = 'neutral' OR naming_policy_version < $3)
          AND status = 'active'`,
      [input.plazaId, input.retryAfter, input.policyVersion]
    );
  }

  private async ensurePlaza(
    transaction: QueryExecutor,
    version: PlazaGridVersion,
    cell: PlazaCell
  ): Promise<void> {
    await transaction.query(
      "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))",
      [`plaza:${version.id}:${cell.gridX}:${cell.gridY}`]
    );
    const existing = await transaction.query(
      `SELECT 1 FROM plaza_grids
        WHERE grid_version_id = $1 AND grid_x = $2 AND grid_y = $3`,
      [version.id, cell.gridX, cell.gridY]
    );
    if (existing.rowCount) return;

    const center = this.projector.center(cell, version);
    const conversationId = randomUUID();
    await transaction.query(
      "INSERT INTO conversations (id, type, status) VALUES ($1, 'plaza', 'active')",
      [conversationId]
    );
    await transaction.query(
      `INSERT INTO plaza_grids (
         id, grid_version_id, grid_x, grid_y, conversation_id, display_name,
         naming_source, center_longitude_gcj02, center_latitude_gcj02, status
       ) VALUES ($1, $2, $3, $4, $5, $6, 'neutral', $7, $8, 'active')`,
      [
        randomUUID(),
        version.id,
        cell.gridX,
        cell.gridY,
        conversationId,
        this.neutralName(version, cell),
        center.longitude,
        center.latitude
      ]
    );
  }

  private plazaSelect(): string {
    return `SELECT grid.id AS plaza_id,
                   grid.conversation_id,
                   grid.display_name,
                   grid.grid_x,
                   grid.grid_y,
                   conversation.latest_sequence,
                   COALESCE(cursor.last_read_sequence, 0) AS last_read_sequence,
                   COALESCE(unread.unread_count, 0) AS unread_count,
                   unread.first_unread_sequence,
                   CASE
                     WHEN setting.notification_override = 'normal' THEN 'normal'
                     WHEN setting.notification_override = 'muted' THEN 'muted'
                     WHEN COALESCE(privacy.global_group_muted, false) THEN 'muted'
                     ELSE 'normal'
                   END AS notification_mode
              FROM plaza_grids grid
              JOIN conversations conversation ON conversation.id = grid.conversation_id
         LEFT JOIN user_privacy_settings privacy ON privacy.user_id = $1
         LEFT JOIN conversation_read_cursors cursor
                ON cursor.conversation_id = grid.conversation_id
               AND cursor.user_id = $1
         LEFT JOIN conversation_notification_settings setting
                ON setting.conversation_id = grid.conversation_id
               AND setting.user_id = $1
         LEFT JOIN LATERAL (
                   SELECT count(*) AS unread_count,
                          min(message.sequence) AS first_unread_sequence
                     FROM messages message
                    WHERE message.conversation_id = grid.conversation_id
                      AND message.sender_user_id IS DISTINCT FROM $1
                      AND message.deleted_at IS NULL
                      AND (message.expires_at IS NULL OR message.expires_at > now())
                      AND message.sequence > COALESCE(cursor.last_read_sequence, 0)
                ) unread ON true`;
  }

  private projection(row: PlazaRow): PlazaProjection {
    return {
      plazaId: row.plaza_id,
      conversationId: row.conversation_id,
      name: row.display_name,
      gridX: Number(row.grid_x),
      gridY: Number(row.grid_y),
      latestSequence: Number(row.latest_sequence),
      lastReadSequence: Number(row.last_read_sequence),
      unreadCount: Number(row.unread_count),
      firstUnreadSequence:
        row.first_unread_sequence === null
          ? null
          : Number(row.first_unread_sequence),
      notificationMode: row.notification_mode
    };
  }

  private neutralName(version: PlazaGridVersion, cell: PlazaCell): string {
    const code = createHash("sha256")
      .update(`${version.version}:${cell.gridX}:${cell.gridY}`)
      .digest("hex")
      .slice(0, 4)
      .toUpperCase();
    return `区域广场 ${code}`;
  }

  private dateOrNull(value: Date | string | null): Date | null {
    return value === null ? null : new Date(value);
  }
}
