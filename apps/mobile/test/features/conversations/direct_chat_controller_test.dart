import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fangyuanli_mobile/src/features/conversations/application/direct_chat_controller.dart';
import 'package:fangyuanli_mobile/src/features/conversations/application/conversation_sync_controller.dart';
import 'package:fangyuanli_mobile/src/features/conversations/data/conversation_repository.dart';
import 'package:fangyuanli_mobile/src/features/conversations/data/conversation_message_store.dart';
import 'package:fangyuanli_mobile/src/features/conversations/domain/conversation_summary.dart';
import 'package:fangyuanli_mobile/src/features/conversations/domain/conversation_message.dart';
import 'package:fangyuanli_mobile/src/core/realtime/realtime_event.dart';

void main() {
  test('loads history, marks it read, and appends a sent message', () async {
    final repository = _FakeConversationRepository();
    final controller = DirectChatController(
      repository,
      'conversation-1',
      const Stream<RealtimeEvent>.empty(),
    );

    await repository.loaded.future;
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.messages.single.text, '你好');
    expect(repository.lastReadSequence, 1);

    expect(await controller.send('  收到  '), isTrue);
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.messages.map((message) => message.text), [
      '你好',
      '收到',
    ]);
    expect(repository.lastReadSequence, 2);

    controller.dispose();
  });

  test('ignores read-receipt failures', () async {
    final repository = _FakeConversationRepository(failMarkRead: true);
    final controller = DirectChatController(
      repository,
      'conversation-1',
      const Stream<RealtimeEvent>.empty(),
    );

    await repository.loaded.future;
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.errorMessage, isNull);
    expect(await controller.send('仍可发送'), isTrue);
    expect(controller.state.errorMessage, isNull);

    controller.dispose();
  });

  test('silent refresh keeps cached messages visible', () async {
    final repository = _FakeConversationRepository();
    final controller = DirectChatController(
      repository,
      'conversation-1',
      const Stream<RealtimeEvent>.empty(),
    );

    await repository.loaded.future;
    await Future<void>.delayed(Duration.zero);
    final refresh = controller.load(silent: true);

    expect(controller.state.messages.single.text, '你好');
    expect(controller.state.isLoading, isFalse);
    expect(controller.state.isRefreshing, isTrue);
    await refresh;
    expect(controller.state.isRefreshing, isFalse);
    expect(repository.loadMessagesCount, 2);

    controller.dispose();
  });

  test(
    'appends a matching realtime message without a manual refresh',
    () async {
      final repository = _FakeConversationRepository();
      final events = StreamController<RealtimeEvent>();
      final controller = DirectChatController(
        repository,
        'conversation-1',
        events.stream,
      );

      await repository.loaded.future;
      await Future<void>.delayed(Duration.zero);
      events.add(
        RealtimeEvent(
          name: 'message.created',
          cursor: '2-0',
          payload: _messageJson(
            id: 'message-realtime',
            sequence: 2,
            senderUserId: 'user-b',
            text: '实时到达',
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.messages.map((message) => message.text), [
        '你好',
        '实时到达',
      ]);
      expect(repository.lastReadSequence, 2);

      await events.close();
      controller.dispose();
    },
  );

  test(
    'renders a persistent snapshot before incrementally syncing newer messages',
    () async {
      final cached = _message(
        id: 'message-cached',
        sequence: 7,
        senderUserId: 'user-b',
        text: '本地消息',
      );
      final store = _MemoryConversationMessageStore(
        ConversationMessageSnapshot(messages: [cached], hasEarlier: true),
      );
      final repository = _IncrementalConversationRepository();
      final controller = DirectChatController(
        repository,
        'conversation-1',
        const Stream<RealtimeEvent>.empty(),
        messageStore: store,
        ownerUserId: 'owner-a',
      );

      await _waitFor(() => repository.afterSequence == 7);
      expect(controller.state.messages.single.text, '本地消息');
      expect(controller.state.isLoading, isFalse);
      expect(controller.state.isRefreshing, isTrue);

      repository.complete(
        ConversationMessagePage(
          items: [
            _message(
              id: 'message-new',
              sequence: 8,
              senderUserId: 'user-b',
              text: '服务器新增',
            ),
          ],
          hasEarlier: true,
          hasLater: false,
        ),
      );
      await _waitFor(() => controller.state.messages.length == 2);

      expect(controller.state.messages.map((message) => message.sequence), [
        7,
        8,
      ]);
      expect(store.lastWritten.map((message) => message.sequence), [7, 8]);
      expect(store.lastOwnerUserId, 'owner-a');
      expect(controller.state.hasEarlier, isTrue);

      controller.dispose();
    },
  );

  test(
    'plaza adapter reuses the sync engine and forwards its location context',
    () async {
      final repository = _FakeConversationRepository();
      final controller = ConversationSyncController(
        repository,
        'plaza-conversation-1',
        const Stream<RealtimeEvent>.empty(),
        accessContext: const ConversationAccessContext.plaza(
          locationContextToken: 'opaque-location-context',
        ),
      );

      await repository.loaded.future;
      await Future<void>.delayed(Duration.zero);
      expect(repository.lastAccess?.scene, ConversationScene.plaza);
      expect(
        repository.lastAccess?.locationContextToken,
        'opaque-location-context',
      );

      expect(await controller.send('广场消息'), isTrue);
      expect(repository.lastAccess?.scene, ConversationScene.plaza);

      controller.dispose();
    },
  );
}

class _IncrementalConversationRepository implements ConversationRepository {
  final _response = Completer<ConversationMessagePage>();
  int? afterSequence;

  void complete(ConversationMessagePage page) => _response.complete(page);

  @override
  Future<ConversationMessagePage> loadMessages(
    String conversationId, {
    int? beforeSequence,
    int? afterSequence,
    int? anchorSequence,
    int limit = 50,
    ConversationAccessContext access = const ConversationAccessContext.direct(),
  }) {
    this.afterSequence = afterSequence;
    return _response.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemoryConversationMessageStore implements ConversationMessageStore {
  _MemoryConversationMessageStore(this.snapshot);

  final ConversationMessageSnapshot? snapshot;
  List<ConversationMessage> lastWritten = const [];
  String? lastOwnerUserId;

  @override
  Future<ConversationMessageSnapshot?> readRecent({
    required String ownerUserId,
    required String conversationId,
    int limit = 50,
  }) async => snapshot;

  @override
  Future<void> write({
    required String ownerUserId,
    required String conversationId,
    required Iterable<ConversationMessage> messages,
    required bool hasEarlier,
  }) async {
    lastOwnerUserId = ownerUserId;
    lastWritten = messages.toList(growable: false);
  }

  @override
  Future<void> clearOwner(String ownerUserId) async {}
}

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 50; attempt += 1) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  fail('condition was not met');
}

class _FakeConversationRepository implements ConversationRepository {
  _FakeConversationRepository({this.failMarkRead = false});

  final bool failMarkRead;
  final Completer<void> loaded = Completer<void>();
  int? lastReadSequence;
  int loadMessagesCount = 0;
  ConversationAccessContext? lastAccess;

  @override
  Future<ConversationListPage> loadConversations() {
    return Future.value(
      const ConversationListPage(
        items: [],
        navigationUnread: 0,
        hasMore: false,
      ),
    );
  }

  @override
  Future<ConversationMessagePage> loadMessages(
    String conversationId, {
    int? beforeSequence,
    int? afterSequence,
    int? anchorSequence,
    int limit = 50,
    ConversationAccessContext access = const ConversationAccessContext.direct(),
  }) async {
    lastAccess = access;
    loadMessagesCount += 1;
    if (!loaded.isCompleted) loaded.complete();
    return ConversationMessagePage(
      items: [
        _message(
          id: 'message-1',
          sequence: 1,
          senderUserId: 'user-b',
          text: '你好',
        ),
      ],
      hasEarlier: false,
      hasLater: false,
    );
  }

  @override
  Future<void> markRead(
    String conversationId,
    int lastReadSequence, {
    ConversationAccessContext access = const ConversationAccessContext.direct(),
  }) async {
    lastAccess = access;
    if (failMarkRead) throw StateError('read receipt unavailable');
    this.lastReadSequence = lastReadSequence;
  }

  @override
  Future<ConversationMessage> sendText(
    String conversationId,
    String text, {
    ConversationAccessContext access = const ConversationAccessContext.direct(),
  }) async {
    lastAccess = access;
    return _message(
      id: 'message-2',
      sequence: 2,
      senderUserId: 'user-a',
      text: text.trim(),
    );
  }
}

ConversationMessage _message({
  required String id,
  required int sequence,
  required String senderUserId,
  required String text,
}) {
  return ConversationMessage(
    messageId: id,
    conversationId: 'conversation-1',
    senderUserId: senderUserId,
    senderName: senderUserId == 'user-a' ? 'A' : 'B',
    sequence: sequence,
    text: text,
    createdAt: DateTime.utc(2026, 7, 29, 12, sequence),
    deliveryState: 'sent',
  );
}

Map<String, dynamic> _messageJson({
  required String id,
  required int sequence,
  required String senderUserId,
  required String text,
}) {
  return {
    'messageId': id,
    'conversationId': 'conversation-1',
    'sequence': sequence,
    'sender': {'userId': senderUserId, 'displayName': 'B'},
    'text': text,
    'createdAt': '2026-07-30T00:00:00.000Z',
    'deliveryState': 'sent',
  };
}
