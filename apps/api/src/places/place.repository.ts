import { Injectable } from "@nestjs/common";
import { randomUUID } from "node:crypto";
import { DatabaseService } from "../database/database.service.js";
import type { QueryExecutor } from "../database/database.types.js";
import type {
  PlaceCandidate,
  PlaceDiscoverQuery,
  PlaceHeatLevel,
  PlaceProjection
} from "./place.types.js";

type PlaceRow = {
  place_group_id: string;
  conversation_id: string;
  name: string;
  address: string | null;
  category_key: PlaceProjection["categoryKey"];
  category_name: string;
  longitude_gcj02: string;
  latitude_gcj02: string;
  certification_status:
    | "unverified"
    | "review_pending"
    | "verified"
    | "rejected"
    | "revoked";
  heat_level: "quiet" | "neutral" | "active" | "very_active" | "hot";
  latest_sequence: string;
  last_read_sequence: string;
  notification_mode: "normal" | "muted";
  role: "owner" | "admin" | "resident" | "member" | null;
  speak_policy: "nearby_and_members" | "members_only" | "admins_only";
  visibility_radius_meters: number;
  version: number;
};

const MAX_DISCOVERY_CANDIDATES = 500;

@Injectable()
export class PlaceRepository {
  constructor(private readonly database: DatabaseService) {}

  async findActiveAround(input: {
    userId: string;
    query: PlaceDiscoverQuery;
  }): Promise<PlaceProjection[]> {
    const { latitude, longitude } = input.query.location;
    const latitudeDelta = input.query.distanceMeters / 111_320;
    const longitudeScale = Math.max(
      0.01,
      Math.cos((latitude * Math.PI) / 180)
    );
    const longitudeDelta = input.query.distanceMeters / (111_320 * longitudeScale);
    const keyword = input.query.keyword ? `%${input.query.keyword}%` : null;
    const heatLevels = input.query.heatLevels.map((level) => this.heatLevelToDb(level));

    const result = await this.database.query<PlaceRow>(
      `SELECT pg.id AS place_group_id,
              pg.conversation_id,
              poi.name,
              poi.address,
              poi.display_category_key AS category_key,
              category.display_name AS category_name,
              poi.longitude_gcj02,
              poi.latitude_gcj02,
              pg.certification_status,
              COALESCE(heat.level, 'quiet') AS heat_level,
              conversation.latest_sequence,
              COALESCE(cursor.last_read_sequence, 0) AS last_read_sequence,
              CASE
                WHEN setting.notification_override = 'normal' THEN 'normal'
                WHEN setting.notification_override = 'muted' THEN 'muted'
                WHEN privacy.global_group_muted THEN 'muted'
                ELSE 'normal'
              END AS notification_mode,
              member.role,
              pg.speak_policy,
              pg.visibility_radius_meters,
              pg.version
         FROM place_groups pg
         JOIN place_pois poi ON poi.id = pg.poi_id
         JOIN place_categories category ON category.key = poi.display_category_key
         JOIN conversations conversation ON conversation.id = pg.conversation_id
         JOIN user_privacy_settings privacy ON privacy.user_id = $1
    LEFT JOIN conversation_read_cursors cursor
           ON cursor.conversation_id = pg.conversation_id
          AND cursor.user_id = $1
    LEFT JOIN conversation_notification_settings setting
           ON setting.conversation_id = pg.conversation_id
          AND setting.user_id = $1
    LEFT JOIN place_group_members member
           ON member.place_group_id = pg.id
          AND member.user_id = $1
          AND member.status = 'active'
    LEFT JOIN LATERAL (
              SELECT snapshot.level
                FROM place_heat_snapshots snapshot
               WHERE snapshot.place_group_id = pg.id
            ORDER BY snapshot.calculated_at DESC
               LIMIT 1
              ) heat ON true
        WHERE pg.visibility_status = 'active'
          AND conversation.status = 'active'
          AND poi.latitude_gcj02 BETWEEN $2 AND $3
          AND poi.longitude_gcj02 BETWEEN $4 AND $5
          AND (cardinality($6::text[]) = 0 OR poi.display_category_key = ANY($6::text[]))
          AND ($7::text IS NULL OR poi.name ILIKE $7 OR COALESCE(poi.address, '') ILIKE $7)
          AND (cardinality($8::text[]) = 0 OR COALESCE(heat.level, 'quiet') = ANY($8::text[]))
          AND ($9::boolean = false OR cursor.conversation_id IS NOT NULL)
     ORDER BY pg.id
        LIMIT $10`,
      [
        input.userId,
        latitude - latitudeDelta,
        latitude + latitudeDelta,
        longitude - longitudeDelta,
        longitude + longitudeDelta,
        input.query.categoryKeys,
        keyword,
        heatLevels,
        input.query.historyOnly,
        MAX_DISCOVERY_CANDIDATES
      ]
    );
    return result.rows.map((row) => this.projection(row));
  }

  async activateCandidates(candidates: PlaceCandidate[]): Promise<void> {
    const uniqueCandidates = [
      ...new Map(candidates.map((candidate) => [candidate.providerPlaceId, candidate])).values()
    ];
    if (uniqueCandidates.length === 0) return;

    await this.database.transaction(async (transaction) => {
      for (const candidate of uniqueCandidates) {
        await this.activateCandidate(transaction, candidate);
      }
    });
  }

  private async activateCandidate(
    transaction: QueryExecutor,
    candidate: PlaceCandidate
  ): Promise<void> {
    await transaction.query(
      "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))",
      [`${candidate.provider}:${candidate.providerPlaceId}`]
    );
    const poiId = randomUUID();
    const poiResult = await transaction.query<{ id: string }>(
      `INSERT INTO place_pois (
         id, amap_poi_id, name, address, longitude_gcj02, latitude_gcj02,
         coordinate_system, amap_category_code, amap_category_name,
         display_category_key, source_updated_at, created_at, updated_at
       ) VALUES ($1, $2, $3, $4, $5, $6, 'gcj02', $7, $8, $9, $10, now(), now())
       ON CONFLICT (amap_poi_id) DO UPDATE
         SET name = EXCLUDED.name,
             address = EXCLUDED.address,
             longitude_gcj02 = EXCLUDED.longitude_gcj02,
             latitude_gcj02 = EXCLUDED.latitude_gcj02,
             amap_category_code = EXCLUDED.amap_category_code,
             amap_category_name = EXCLUDED.amap_category_name,
             display_category_key = EXCLUDED.display_category_key,
             source_updated_at = EXCLUDED.source_updated_at,
             updated_at = now()
       RETURNING id`,
      [
        poiId,
        candidate.providerPlaceId,
        candidate.name,
        candidate.address,
        candidate.longitude,
        candidate.latitude,
        candidate.rawCategoryCode,
        candidate.rawCategoryName,
        candidate.categoryKey,
        candidate.sourceUpdatedAt
      ]
    );
    const resolvedPoiId = poiResult.rows[0]?.id;
    if (!resolvedPoiId) throw new Error("Failed to persist place POI");
    const existing = await transaction.query(
      "SELECT 1 FROM place_groups WHERE poi_id = $1",
      [resolvedPoiId]
    );
    if (existing.rowCount) return;

    const conversationId = randomUUID();
    await transaction.query(
      `INSERT INTO conversations (id, type, status)
       VALUES ($1, 'place', 'active')`,
      [conversationId]
    );
    await transaction.query(
      `INSERT INTO place_groups (
         id, poi_id, conversation_id, certification_status, visibility_status,
         visibility_radius_meters, speak_policy, version, created_at, updated_at
       ) VALUES ($1, $2, $3, 'unverified', 'active', 500,
                 'nearby_and_members', 1, now(), now())`,
      [randomUUID(), resolvedPoiId, conversationId]
    );
  }

  private projection(row: PlaceRow): PlaceProjection {
    return {
      placeGroupId: row.place_group_id,
      conversationId: row.conversation_id,
      name: row.name,
      address: row.address,
      categoryKey: row.category_key,
      categoryName: row.category_name,
      longitude: Number(row.longitude_gcj02),
      latitude: Number(row.latitude_gcj02),
      certificationStatus:
        row.certification_status === "review_pending"
          ? "reviewPending"
          : row.certification_status === "verified"
            ? "verified"
            : "unverified",
      heatLevel: this.heatLevelFromDb(row.heat_level),
      latestSequence: Number(row.latest_sequence),
      lastReadSequence: Number(row.last_read_sequence),
      notificationMode: row.notification_mode,
      role: row.role,
      speakPolicy:
        row.speak_policy === "nearby_and_members"
          ? "nearbyAndMembers"
          : row.speak_policy === "members_only"
            ? "membersOnly"
            : "adminsOnly",
      visibilityRadiusMeters: row.visibility_radius_meters,
      version: row.version
    };
  }

  private heatLevelToDb(level: PlaceHeatLevel): string {
    return level === "veryActive" ? "very_active" : level;
  }

  private heatLevelFromDb(level: PlaceRow["heat_level"]): PlaceHeatLevel {
    return level === "very_active" ? "veryActive" : level;
  }
}
