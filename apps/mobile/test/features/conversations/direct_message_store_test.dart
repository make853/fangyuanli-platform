import 'dart:io';

import 'package:fangyuanli_mobile/src/core/storage/app_database.dart';
import 'package:fangyuanli_mobile/src/features/conversations/data/direct_message_store.dart';
import 'package:fangyuanli_mobile/src/features/conversations/domain/direct_message.dart';
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
    final store = SqliteDirectMessageStore(appDatabase);
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
      final store = SqliteDirectMessageStore(appDatabase);
      await store.write(
        ownerUserId: 'owner-a',
        conversationId: 'conversation-1',
        messages: [_message(sequence: 1), _message(sequence: 2)],
        hasEarlier: false,
      );
      final database = await appDatabase.open();
      await database.update(
        'direct_messages',
        {'payload_json': '{broken'},
        where: 'owner_user_id = ? AND conversation_id = ? AND sequence = ?',
        whereArgs: ['owner-a', 'conversation-1', 2],
      );

      expect(
        await store.readRecent(
          ownerUserId: 'owner-a',
          conversationId: 'conversation-1',
        ),
        isNull,
      );
      expect(
        await database.query(
          'direct_messages',
          where: 'owner_user_id = ? AND conversation_id = ?',
          whereArgs: ['owner-a', 'conversation-1'],
        ),
        isEmpty,
      );

      await appDatabase.close();
      await directory.delete(recursive: true);
    },
  );
}

DirectMessage _message({required int sequence}) {
  return DirectMessage(
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
