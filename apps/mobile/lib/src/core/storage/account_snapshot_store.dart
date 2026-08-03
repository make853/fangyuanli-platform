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
  AccountSnapshotRecord? peek({
    required String ownerUserId,
    required String snapshotKey,
  });

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
  SqliteAccountSnapshotStore(this._appDatabase);

  final AppDatabase _appDatabase;
  final Map<String, AccountSnapshotRecord> _memory = {};

  String _key(String ownerUserId, String snapshotKey) =>
      '$ownerUserId\u0000$snapshotKey';

  @override
  AccountSnapshotRecord? peek({
    required String ownerUserId,
    required String snapshotKey,
  }) => _memory[_key(ownerUserId, snapshotKey)];

  @override
  Future<AccountSnapshotRecord?> read({
    required String ownerUserId,
    required String snapshotKey,
  }) async {
    final memory = peek(ownerUserId: ownerUserId, snapshotKey: snapshotKey);
    if (memory != null) return memory;
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
      final record = AccountSnapshotRecord(
        payloadVersion: rows.single['payload_version']! as int,
        payload: Map<String, dynamic>.from(decoded as Map),
      );
      _memory[_key(ownerUserId, snapshotKey)] = record;
      return record;
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
    _memory[_key(ownerUserId, snapshotKey)] = AccountSnapshotRecord(
      payloadVersion: payloadVersion,
      payload: Map.unmodifiable(Map<String, dynamic>.from(payload)),
    );
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
    _memory.remove(_key(ownerUserId, snapshotKey));
    final database = await _appDatabase.open();
    await database.delete(
      'account_snapshots',
      where: 'owner_user_id = ? AND snapshot_key = ?',
      whereArgs: [ownerUserId, snapshotKey],
    );
  }

  @override
  Future<void> clearOwner(String ownerUserId) async {
    _memory.removeWhere((key, _) => key.startsWith('$ownerUserId\u0000'));
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
