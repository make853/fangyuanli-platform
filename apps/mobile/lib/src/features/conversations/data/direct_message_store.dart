import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/storage/app_database.dart';
import '../domain/direct_message.dart';

class DirectMessageSnapshot {
  const DirectMessageSnapshot({
    required this.messages,
    required this.hasEarlier,
  });

  final List<DirectMessage> messages;
  final bool hasEarlier;
}

abstract interface class DirectMessageStore {
  Future<DirectMessageSnapshot?> readRecent({
    required String ownerUserId,
    required String conversationId,
    int limit = 50,
  });

  Future<void> write({
    required String ownerUserId,
    required String conversationId,
    required Iterable<DirectMessage> messages,
    required bool hasEarlier,
  });

  Future<void> clearOwner(String ownerUserId);
}

class SqliteDirectMessageStore implements DirectMessageStore {
  const SqliteDirectMessageStore(this._appDatabase);

  final AppDatabase _appDatabase;

  @override
  Future<DirectMessageSnapshot?> readRecent({
    required String ownerUserId,
    required String conversationId,
    int limit = 50,
  }) async {
    final database = await _appDatabase.open();
    final threadRows = await database.query(
      'direct_message_threads',
      columns: const ['has_earlier'],
      where: 'owner_user_id = ? AND conversation_id = ?',
      whereArgs: [ownerUserId, conversationId],
      limit: 1,
    );
    if (threadRows.isEmpty) return null;

    final rows = await database.query(
      'direct_messages',
      columns: const ['message_id', 'payload_json'],
      where: 'owner_user_id = ? AND conversation_id = ?',
      whereArgs: [ownerUserId, conversationId],
      orderBy: 'sequence DESC',
      limit: limit,
    );
    final messages = <DirectMessage>[];
    var corrupted = false;
    for (final row in rows.reversed) {
      try {
        final payload = jsonDecode(row['payload_json']! as String);
        messages.add(
          DirectMessage.fromJson(Map<String, dynamic>.from(payload as Map)),
        );
      } on Object {
        corrupted = true;
      }
    }
    if (corrupted) {
      await database.transaction((transaction) async {
        await transaction.delete(
          'direct_messages',
          where: 'owner_user_id = ? AND conversation_id = ?',
          whereArgs: [ownerUserId, conversationId],
        );
        await transaction.delete(
          'direct_message_threads',
          where: 'owner_user_id = ? AND conversation_id = ?',
          whereArgs: [ownerUserId, conversationId],
        );
      });
      return null;
    }
    if (messages.isEmpty) return null;
    return DirectMessageSnapshot(
      messages: messages,
      hasEarlier: (threadRows.single['has_earlier'] as int) != 0,
    );
  }

  @override
  Future<void> write({
    required String ownerUserId,
    required String conversationId,
    required Iterable<DirectMessage> messages,
    required bool hasEarlier,
  }) async {
    final items = messages.toList(growable: false);
    if (items.isEmpty) return;
    final database = await _appDatabase.open();
    await database.transaction((transaction) async {
      for (final message in items) {
        await transaction.insert('direct_messages', {
          'owner_user_id': ownerUserId,
          'conversation_id': conversationId,
          'message_id': message.messageId,
          'sequence': message.sequence,
          'payload_json': jsonEncode(message.toJson()),
          'created_at_ms': message.createdAt.toUtc().millisecondsSinceEpoch,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      final existing = await transaction.query(
        'direct_message_threads',
        columns: const ['latest_sequence', 'has_earlier'],
        where: 'owner_user_id = ? AND conversation_id = ?',
        whereArgs: [ownerUserId, conversationId],
        limit: 1,
      );
      final batchLatest = items
          .map((message) => message.sequence)
          .reduce((left, right) => left > right ? left : right);
      final existingLatest = existing.isEmpty
          ? 0
          : existing.single['latest_sequence']! as int;
      final existingHasEarlier =
          existing.isNotEmpty && (existing.single['has_earlier']! as int) != 0;
      await transaction.insert('direct_message_threads', {
        'owner_user_id': ownerUserId,
        'conversation_id': conversationId,
        'latest_sequence': batchLatest > existingLatest
            ? batchLatest
            : existingLatest,
        'has_earlier': existingHasEarlier || hasEarlier ? 1 : 0,
        'cached_at_ms': DateTime.now().toUtc().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  @override
  Future<void> clearOwner(String ownerUserId) async {
    final database = await _appDatabase.open();
    await database.transaction((transaction) async {
      await transaction.delete(
        'direct_messages',
        where: 'owner_user_id = ?',
        whereArgs: [ownerUserId],
      );
      await transaction.delete(
        'direct_message_threads',
        where: 'owner_user_id = ?',
        whereArgs: [ownerUserId],
      );
    });
  }
}

final directMessageStoreProvider = Provider<DirectMessageStore>((ref) {
  return SqliteDirectMessageStore(ref.watch(appDatabaseProvider));
});
