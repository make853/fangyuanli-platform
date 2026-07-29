import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fangyuanli_mobile/src/features/conversations/application/direct_chat_controller.dart';
import 'package:fangyuanli_mobile/src/features/conversations/data/conversation_repository.dart';
import 'package:fangyuanli_mobile/src/features/conversations/domain/direct_message.dart';

void main() {
  test('loads history, marks it read, and appends a sent message', () async {
    final repository = _FakeConversationRepository();
    final controller = DirectChatController(repository, 'conversation-1');

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
    final controller = DirectChatController(repository, 'conversation-1');

    await repository.loaded.future;
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.errorMessage, isNull);
    expect(await controller.send('仍可发送'), isTrue);
    expect(controller.state.errorMessage, isNull);

    controller.dispose();
  });
}

class _FakeConversationRepository implements ConversationRepository {
  _FakeConversationRepository({this.failMarkRead = false});

  final bool failMarkRead;
  final Completer<void> loaded = Completer<void>();
  int? lastReadSequence;

  @override
  Future<DirectMessagePage> loadMessages(String conversationId) async {
    if (!loaded.isCompleted) loaded.complete();
    return DirectMessagePage(
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
  Future<void> markRead(String conversationId, int lastReadSequence) async {
    if (failMarkRead) throw StateError('read receipt unavailable');
    this.lastReadSequence = lastReadSequence;
  }

  @override
  Future<DirectMessage> sendText(String conversationId, String text) async {
    return _message(
      id: 'message-2',
      sequence: 2,
      senderUserId: 'user-a',
      text: text.trim(),
    );
  }
}

DirectMessage _message({
  required String id,
  required int sequence,
  required String senderUserId,
  required String text,
}) {
  return DirectMessage(
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
