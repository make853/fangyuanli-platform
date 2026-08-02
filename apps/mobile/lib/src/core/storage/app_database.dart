import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// The single account-scoped local persistence boundary for the mobile app.
///
/// New durable client-side stores must add a schema migration here instead of
/// opening feature-specific databases. Server data remains authoritative; this
/// database exists to render stable local snapshots and support offline use.
class AppDatabase {
  AppDatabase({
    this.databaseFactoryOverride,
    Future<String> Function()? pathLoader,
  }) : _pathLoader = pathLoader ?? _defaultPath;

  static const schemaVersion = 4;

  final DatabaseFactory? databaseFactoryOverride;
  final Future<String> Function() _pathLoader;
  Future<Database>? _opening;

  Future<Database> open() => _opening ??= _open();

  Future<Database> _open() async {
    final databasePath = await _pathLoader();
    final factory = databaseFactoryOverride ?? databaseFactory;
    return factory.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (database) async {
          await database.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (database, version) async {
          await _upgrade(database, 0, version);
        },
        onUpgrade: (database, oldVersion, newVersion) async {
          await _upgrade(database, oldVersion, newVersion);
        },
      ),
    );
  }

  static Future<void> _createVersionOne(Database database) async {
    await database.execute('''
      CREATE TABLE user_profile_snapshots (
        owner_user_id TEXT NOT NULL,
        target_user_id TEXT NOT NULL,
        profile_version INTEGER NOT NULL,
        payload_json TEXT NOT NULL,
        cached_at_ms INTEGER NOT NULL,
        PRIMARY KEY (owner_user_id, target_user_id)
      )
    ''');
    await database.execute('''
      CREATE INDEX idx_user_profile_snapshots_cached_at
      ON user_profile_snapshots (owner_user_id, cached_at_ms)
    ''');
  }

  static Future<void> _createVersionTwo(Database database) async {
    await database.execute('''
      CREATE TABLE direct_message_threads (
        owner_user_id TEXT NOT NULL,
        conversation_id TEXT NOT NULL,
        latest_sequence INTEGER NOT NULL,
        has_earlier INTEGER NOT NULL,
        cached_at_ms INTEGER NOT NULL,
        PRIMARY KEY (owner_user_id, conversation_id)
      )
    ''');
    await database.execute('''
      CREATE TABLE direct_messages (
        owner_user_id TEXT NOT NULL,
        conversation_id TEXT NOT NULL,
        message_id TEXT NOT NULL,
        sequence INTEGER NOT NULL,
        payload_json TEXT NOT NULL,
        created_at_ms INTEGER NOT NULL,
        PRIMARY KEY (owner_user_id, conversation_id, message_id),
        UNIQUE (owner_user_id, conversation_id, sequence)
      )
    ''');
    await database.execute('''
      CREATE INDEX idx_direct_messages_sequence
      ON direct_messages (owner_user_id, conversation_id, sequence DESC)
    ''');
  }

  static Future<void> _createVersionThree(Database database) async {
    await database.execute('''
      CREATE TABLE account_snapshots (
        owner_user_id TEXT NOT NULL,
        snapshot_key TEXT NOT NULL,
        payload_version INTEGER NOT NULL,
        payload_json TEXT NOT NULL,
        cached_at_ms INTEGER NOT NULL,
        PRIMARY KEY (owner_user_id, snapshot_key)
      )
    ''');
    await database.execute('''
      CREATE INDEX idx_account_snapshots_cached_at
      ON account_snapshots (owner_user_id, cached_at_ms)
    ''');
  }

  static Future<void> _createVersionFour(Database database) async {
    // The v2 tables originally carried a direct-chat name even though their
    // keys and payloads were already conversation-scoped. Rename them in place
    // so installed users keep every cached message while all conversation
    // scenes share one physical store.
    await database.execute(
      'ALTER TABLE direct_message_threads RENAME TO conversation_threads',
    );
    await database.execute(
      'ALTER TABLE direct_messages RENAME TO conversation_messages',
    );
    await database.execute('DROP INDEX idx_direct_messages_sequence');
    await database.execute('''
      CREATE INDEX idx_conversation_messages_sequence
      ON conversation_messages (owner_user_id, conversation_id, sequence DESC)
    ''');
  }

  static Future<void> _upgrade(
    Database database,
    int oldVersion,
    int newVersion,
  ) async {
    var migratedVersion = oldVersion;
    // Add future migrations one version at a time. Never use destructive
    // recreation for an installed user's local messages or profile snapshots.
    if (migratedVersion < 1) {
      await _createVersionOne(database);
      migratedVersion = 1;
    }
    if (migratedVersion < 2) {
      await _createVersionTwo(database);
      migratedVersion = 2;
    }
    if (migratedVersion < 3) {
      await _createVersionThree(database);
      migratedVersion = 3;
    }
    if (migratedVersion < 4) {
      await _createVersionFour(database);
      migratedVersion = 4;
    }
    if (migratedVersion != newVersion) {
      throw StateError(
        'Missing local database migration: $migratedVersion -> $newVersion',
      );
    }
  }

  Future<void> close() async {
    final opening = _opening;
    _opening = null;
    if (opening == null) return;
    try {
      final database = await opening;
      await database.close();
    } catch (_) {
      // Opening may fail in tests or on damaged storage; disposal stays safe.
    }
  }

  static Future<String> _defaultPath() async {
    final support = await getApplicationSupportDirectory();
    return path.join(support.path, 'fangyuanli_local.v1.db');
  }
}

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase();
  ref.onDispose(() => unawaited(database.close()));
  return database;
});
