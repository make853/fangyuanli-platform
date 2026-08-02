import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/storage/app_database.dart';
import '../domain/profile_models.dart';

abstract interface class ProfileSnapshotStore {
  Future<UserProfile?> read({
    required String ownerUserId,
    required String targetUserId,
  });

  Future<void> write({
    required String ownerUserId,
    required UserProfile profile,
  });

  Future<void> clearOwner(String ownerUserId);
}

class SqliteProfileSnapshotStore implements ProfileSnapshotStore {
  const SqliteProfileSnapshotStore(this._appDatabase);

  final AppDatabase _appDatabase;

  @override
  Future<UserProfile?> read({
    required String ownerUserId,
    required String targetUserId,
  }) async {
    final database = await _appDatabase.open();
    final rows = await database.query(
      'user_profile_snapshots',
      columns: const ['payload_json'],
      where: 'owner_user_id = ? AND target_user_id = ?',
      whereArgs: [ownerUserId, targetUserId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    try {
      final payload = jsonDecode(rows.single['payload_json']! as String);
      return UserProfile.fromJson(Map<String, dynamic>.from(payload as Map));
    } on Object {
      await database.delete(
        'user_profile_snapshots',
        where: 'owner_user_id = ? AND target_user_id = ?',
        whereArgs: [ownerUserId, targetUserId],
      );
      return null;
    }
  }

  @override
  Future<void> write({
    required String ownerUserId,
    required UserProfile profile,
  }) async {
    final database = await _appDatabase.open();
    await database.transaction((transaction) async {
      final existing = await transaction.query(
        'user_profile_snapshots',
        columns: const ['profile_version'],
        where: 'owner_user_id = ? AND target_user_id = ?',
        whereArgs: [ownerUserId, profile.userId],
        limit: 1,
      );
      final existingVersion = existing.isEmpty
          ? null
          : existing.single['profile_version']! as int;
      if (existingVersion != null && existingVersion > profile.profileVersion) {
        return;
      }
      await transaction.insert('user_profile_snapshots', {
        'owner_user_id': ownerUserId,
        'target_user_id': profile.userId,
        'profile_version': profile.profileVersion,
        'payload_json': jsonEncode(profile.toJson()),
        'cached_at_ms': DateTime.now().toUtc().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  @override
  Future<void> clearOwner(String ownerUserId) async {
    final database = await _appDatabase.open();
    await database.delete(
      'user_profile_snapshots',
      where: 'owner_user_id = ?',
      whereArgs: [ownerUserId],
    );
  }
}

final profileSnapshotStoreProvider = Provider<ProfileSnapshotStore>((ref) {
  return SqliteProfileSnapshotStore(ref.watch(appDatabaseProvider));
});
