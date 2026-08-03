import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/storage/app_database.dart';
import 'conversation_message_store.dart';
import '../domain/conversation_message.dart';

/// Durable client outbox shared by direct, plaza, place and activity chats.
///
/// Confirmed server messages stay in [ConversationMessageStore]. Keeping the
/// outbox separate means a local optimistic message never invents a server
/// sequence or contaminates authoritative history pagination.
abstract interface class ConversationOutboxStore {
  List<ConversationMessage> peek({
    required String ownerUserId,
    required String conversationId,
  });

  Future<List<ConversationMessage>> read({
    required String ownerUserId,
    required String conversationId,
  });

  Future<void> upsert({
    required String ownerUserId,
    required ConversationMessage message,
  });

  Future<void> delete({
    required String ownerUserId,
    required String conversationId,
    required String clientMessageId,
  });

  Future<void> clearOwner(String ownerUserId);
}

class SqliteConversationOutboxStore implements ConversationOutboxStore {
  SqliteConversationOutboxStore(this._appDatabase);

  final AppDatabase _appDatabase;
  final Map<String, List<ConversationMessage>> _memory = {};

  String _key(String ownerUserId, String conversationId) =>
      '$ownerUserId\u0000$conversationId';

  @override
  List<ConversationMessage> peek({
    required String ownerUserId,
    required String conversationId,
  }) =>
      List.unmodifiable(_memory[_key(ownerUserId, conversationId)] ?? const []);

  @override
  Future<List<ConversationMessage>> read({
    required String ownerUserId,
    required String conversationId,
  }) async {
    final memory = _memory[_key(ownerUserId, conversationId)];
    if (memory != null) return List.unmodifiable(memory);
    final database = await _appDatabase.open();
    final rows = await database.query(
      'conversation_outbox',
      columns: const ['payload_json'],
      where: 'owner_user_id = ? AND conversation_id = ?',
      whereArgs: [ownerUserId, conversationId],
      orderBy: 'created_at_ms ASC',
    );
    final messages = <ConversationMessage>[];
    for (final row in rows) {
      try {
        final decoded = jsonDecode(row['payload_json']! as String);
        messages.add(
          ConversationMessage.fromJson(
            Map<String, dynamic>.from(decoded as Map),
          ),
        );
      } on Object {
        // A damaged local outbox row is isolated and removed below.
      }
    }
    if (messages.length != rows.length) {
      await database.delete(
        'conversation_outbox',
        where: 'owner_user_id = ? AND conversation_id = ?',
        whereArgs: [ownerUserId, conversationId],
      );
      for (final message in messages) {
        await _writeRow(database, ownerUserId, message);
      }
    }
    _memory[_key(ownerUserId, conversationId)] = messages;
    return List.unmodifiable(messages);
  }

  @override
  Future<void> upsert({
    required String ownerUserId,
    required ConversationMessage message,
  }) async {
    final clientMessageId = message.clientMessageId;
    if (clientMessageId == null || clientMessageId.isEmpty) {
      throw ArgumentError.value(clientMessageId, 'clientMessageId');
    }
    final key = _key(ownerUserId, message.conversationId);
    final current = _memory[key] ?? const <ConversationMessage>[];
    _memory[key] = [
      for (final item in current)
        if (item.clientMessageId != clientMessageId) item,
      message,
    ]..sort((left, right) => left.createdAt.compareTo(right.createdAt));
    final database = await _appDatabase.open();
    await _writeRow(database, ownerUserId, message);
  }

  Future<void> _writeRow(
    Database database,
    String ownerUserId,
    ConversationMessage message,
  ) {
    return database.insert('conversation_outbox', {
      'owner_user_id': ownerUserId,
      'conversation_id': message.conversationId,
      'client_message_id': message.clientMessageId,
      'payload_json': jsonEncode(message.toJson()),
      'created_at_ms': message.createdAt.toUtc().millisecondsSinceEpoch,
      'updated_at_ms': DateTime.now().toUtc().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> delete({
    required String ownerUserId,
    required String conversationId,
    required String clientMessageId,
  }) async {
    final key = _key(ownerUserId, conversationId);
    _memory[key] = [
      for (final item in _memory[key] ?? const <ConversationMessage>[])
        if (item.clientMessageId != clientMessageId) item,
    ];
    final database = await _appDatabase.open();
    await database.delete(
      'conversation_outbox',
      where:
          'owner_user_id = ? AND conversation_id = ? AND client_message_id = ?',
      whereArgs: [ownerUserId, conversationId, clientMessageId],
    );
  }

  @override
  Future<void> clearOwner(String ownerUserId) async {
    _memory.removeWhere((key, _) => key.startsWith('$ownerUserId\u0000'));
    final database = await _appDatabase.open();
    await database.delete(
      'conversation_outbox',
      where: 'owner_user_id = ?',
      whereArgs: [ownerUserId],
    );
  }
}

final conversationOutboxStoreProvider = Provider<ConversationOutboxStore>((
  ref,
) {
  return SqliteConversationOutboxStore(ref.watch(appDatabaseProvider));
});
