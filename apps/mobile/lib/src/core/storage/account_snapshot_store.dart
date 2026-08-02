import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import 'app_database.dart';

class AccountSnapshotRecord {
  const AccountSnapshotRecord({
    required this.payloadVersion,
    required this.payload,
  });

  final int payloadVersion;
  final Map<String, dynamic> payload;
}

abstract interface class AccountSnapshotStore {
  Future<AccountSnapshotRecord?> read({
    required String ownerUserId,
    required String snapshotKey,
  });

  Future<void> write({
    required String ownerUserId,
    required String snapshotKey,
    required int payloadVersion,
    required Map<String, dynamic> payload,
  });

  Future<void> delete({
    required String ownerUserId,
    required String snapshotKey,
  });

  Future<void> clearOwner(String ownerUserId);
}

class SqliteAccountSnapshotStore implements AccountSnapshotStore {
  const SqliteAccountSnapshotStore(this._appDatabase);

  final AppDatabase _appDatabase;

  @override
  Future<AccountSnapshotRecord?> read({
    required String ownerUserId,
    required String snapshotKey,
  }) async {
    final database = await _appDatabase.open();
    final rows = await database.query(
      'account_snapshots',
      columns: const ['payload_version', 'payload_json'],
      where: 'owner_user_id = ? AND snapshot_key = ?',
      whereArgs: [ownerUserId, snapshotKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    try {
      final decoded = jsonDecode(rows.single['payload_json']! as String);
      return AccountSnapshotRecord(
        payloadVersion: rows.single['payload_version']! as int,
        payload: Map<String, dynamic>.from(decoded as Map),
      );
    } on Object {
      await delete(ownerUserId: ownerUserId, snapshotKey: snapshotKey);
      return null;
    }
  }

  @override
  Future<void> write({
    required String ownerUserId,
    required String snapshotKey,
    required int payloadVersion,
    required Map<String, dynamic> payload,
  }) async {
    final database = await _appDatabase.open();
    await database.insert('account_snapshots', {
      'owner_user_id': ownerUserId,
      'snapshot_key': snapshotKey,
      'payload_version': payloadVersion,
      'payload_json': jsonEncode(payload),
      'cached_at_ms': DateTime.now().toUtc().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> delete({
    required String ownerUserId,
    required String snapshotKey,
  }) async {
    final database = await _appDatabase.open();
    await database.delete(
      'account_snapshots',
      where: 'owner_user_id = ? AND snapshot_key = ?',
      whereArgs: [ownerUserId, snapshotKey],
    );
  }

  @override
  Future<void> clearOwner(String ownerUserId) async {
    final database = await _appDatabase.open();
    await database.delete(
      'account_snapshots',
      where: 'owner_user_id = ?',
      whereArgs: [ownerUserId],
    );
  }
}

final accountSnapshotStoreProvider = Provider<AccountSnapshotStore>((ref) {
  return SqliteAccountSnapshotStore(ref.watch(appDatabaseProvider));
});
