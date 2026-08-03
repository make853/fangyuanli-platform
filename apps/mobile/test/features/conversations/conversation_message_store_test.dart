import 'dart:convert';
import 'dart:io';

import 'package:fangyuanli_mobile/src/core/storage/app_database.dart';
import 'package:fangyuanli_mobile/src/features/conversations/data/conversation_message_store.dart';
import 'package:fangyuanli_mobile/src/features/conversations/data/conversation_outbox_store.dart';
import 'package:fangyuanli_mobile/src/features/conversations/domain/conversation_message.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('migrates version one and keeps messages isolated by account', () async {
    final directory = await Directory.systemTemp.createTemp(
      'fangyuanli-message-store-',
    );
    final databasePath = '${directory.path}/local.db';
    final versionOne = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (database, _) async {
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
        },
      ),
    );
    await versionOne.close();

    final appDatabase = AppDatabase(
      databaseFactoryOverride: databaseFactoryFfi,
      pathLoader: () async => databasePath,
    );
    final store = SqliteConversationMessageStore(appDatabase);
    final message = _message(sequence: 9);
    await store.write(
      ownerUserId: 'owner-a',
      conversationId: 'conversation-1',
      messages: [message],
      hasEarlier: true,
    );

    final ownerA = await store.readRecent(
      ownerUserId: 'owner-a',
      conversationId: 'conversation-1',
    );
    final ownerB = await store.readRecent(
      ownerUserId: 'owner-b',
      conversationId: 'conversation-1',
    );
    final database = await appDatabase.open();

    expect(await database.getVersion(), AppDatabase.schemaVersion);
    expect(ownerA?.messages.single.text, '消息 9');
    expect(ownerA?.hasEarlier, isTrue);
    expect(ownerB, isNull);

    await appDatabase.close();
    await directory.delete(recursive: true);
  });

  test(
    'renames the v3 direct cache in place without losing messages',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'fangyuanli-message-v3-migration-',
      );
      final databasePath = '${directory.path}/local.db';
      final cached = _message(sequence: 12);
      final versionThree = await databaseFactoryFfi.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(
          version: 3,
          onCreate: (database, _) async {
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
            await database.insert('direct_message_threads', {
              'owner_user_id': 'owner-a',
              'conversation_id': 'conversation-1',
              'latest_sequence': 12,
              'has_earlier': 1,
              'cached_at_ms': 1,
            });
            await database.insert('direct_messages', {
              'owner_user_id': 'owner-a',
              'conversation_id': 'conversation-1',
              'message_id': cached.messageId,
              'sequence': cached.sequence,
              'payload_json': jsonEncode(cached.toJson()),
              'created_at_ms': cached.createdAt.millisecondsSinceEpoch,
            });
          },
        ),
      );
      await versionThree.close();

      final appDatabase = AppDatabase(
        databaseFactoryOverride: databaseFactoryFfi,
        pathLoader: () async => databasePath,
      );
      final store = SqliteConversationMessageStore(appDatabase);
      final restored = await store.readRecent(
        ownerUserId: 'owner-a',
        conversationId: 'conversation-1',
      );
      final database = await appDatabase.open();
      final tables = await database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      final names = tables.map((row) => row['name']);

      expect(await database.getVersion(), AppDatabase.schemaVersion);
      expect(restored?.messages.single.text, '消息 12');
      expect(restored?.hasEarlier, isTrue);
      expect(names, contains('conversation_messages'));
      expect(names, isNot(contains('direct_messages')));

      await appDatabase.close();
      await directory.delete(recursive: true);
    },
  );

  test(
    'discards a damaged conversation cache for a clean network reload',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'fangyuanli-damaged-message-',
      );
      final databasePath = '${directory.path}/local.db';
      final appDatabase = AppDatabase(
        databaseFactoryOverride: databaseFactoryFfi,
        pathLoader: () async => databasePath,
      );
      final store = SqliteConversationMessageStore(appDatabase);
      await store.write(
        ownerUserId: 'owner-a',
        conversationId: 'conversation-1',
        messages: [_message(sequence: 1), _message(sequence: 2)],
        hasEarlier: false,
      );
      final database = await appDatabase.open();
      await database.update(
        'conversation_messages',
        {'payload_json': '{broken'},
        where: 'owner_user_id = ? AND conversation_id = ? AND sequence = ?',
        whereArgs: ['owner-a', 'conversation-1', 2],
      );

      final reopenedStore = SqliteConversationMessageStore(appDatabase);

      expect(
        await reopenedStore.readRecent(
          ownerUserId: 'owner-a',
          conversationId: 'conversation-1',
        ),
        isNull,
      );
      expect(
        await database.query(
          'conversation_messages',
          where: 'owner_user_id = ? AND conversation_id = ?',
          whereArgs: ['owner-a', 'conversation-1'],
        ),
        isEmpty,
      );

      await appDatabase.close();
      await directory.delete(recursive: true);
    },
  );

  test(
    'persists failed optimistic messages separately from server history',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'fangyuanli-outbox-store-',
      );
      final databasePath = '${directory.path}/local.db';
      final appDatabase = AppDatabase(
        databaseFactoryOverride: databaseFactoryFfi,
        pathLoader: () async => databasePath,
      );
      final store = SqliteConversationOutboxStore(appDatabase);
      final pending = ConversationMessage(
        messageId: 'local:client-1',
        clientMessageId: 'client-1',
        conversationId: 'conversation-1',
        sequence: 0,
        senderUserId: 'owner-a',
        senderName: 'A',
        text: '网络断开也要保留',
        createdAt: DateTime.utc(2026, 8, 3, 8),
        deliveryState: 'failed',
      );

      await store.upsert(ownerUserId: 'owner-a', message: pending);
      expect(
        store
            .peek(ownerUserId: 'owner-a', conversationId: 'conversation-1')
            .single
            .deliveryState,
        'failed',
      );
      final reopened = SqliteConversationOutboxStore(appDatabase);
      final restored = await reopened.read(
        ownerUserId: 'owner-a',
        conversationId: 'conversation-1',
      );
      expect(restored.single.clientMessageId, 'client-1');
      expect(restored.single.text, '网络断开也要保留');

      await reopened.delete(
        ownerUserId: 'owner-a',
        conversationId: 'conversation-1',
        clientMessageId: 'client-1',
      );
      expect(
        await reopened.read(
          ownerUserId: 'owner-a',
          conversationId: 'conversation-1',
        ),
        isEmpty,
      );

      await appDatabase.close();
      await directory.delete(recursive: true);
    },
  );
}

ConversationMessage _message({required int sequence}) {
  return ConversationMessage(
    messageId: 'message-$sequence',
    conversationId: 'conversation-1',
    sequence: sequence,
    senderUserId: 'user-b',
    senderName: '小桃子',
    text: '消息 $sequence',
    createdAt: DateTime.utc(2026, 8, 2, 10, sequence),
    deliveryState: 'sent',
  );
}
