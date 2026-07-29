import 'dart:async';

import 'package:fangyuanli_mobile/src/core/realtime/realtime_event.dart';
import 'package:fangyuanli_mobile/src/features/conversations/application/conversation_list_controller.dart';
import 'package:fangyuanli_mobile/src/features/conversations/data/conversation_repository.dart';
import 'package:fangyuanli_mobile/src/features/conversations/domain/conversation_summary.dart';
import 'package:fangyuanli_mobile/src/features/conversations/domain/direct_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps navigation unread and conversation preview consistent', () async {
    final realtime = StreamController<RealtimeEvent>.broadcast(sync: true);
    final repository = _FakeConversationRepository([
      _page(unread: 0, preview: '已读消息'),
      _page(unread: 2, preview: '新消息'),
    ]);
    final controller = ConversationListController(repository, realtime.stream);

    await _waitFor(
      () =>
          controller.state.items.isNotEmpty &&
          controller.state.items.single.lastMessage?.preview == '已读消息',
    );
    expect(controller.state.navigationUnread, 0);

    realtime.add(
      const RealtimeEvent(
        name: 'conversation.unread.changed',
        cursor: '41-0',
        payload: {'navigationUnreadCount': 2},
      ),
    );
    expect(controller.state.navigationUnread, 2);
    await _waitFor(
      () => controller.state.items.single.lastMessage?.preview == '新消息',
    );

    expect(controller.state.navigationUnread, 2);
    expect(controller.state.items.single.lastMessage?.preview, '新消息');

    controller.dispose();
    await realtime.close();
  });

  test('debounces duplicate realtime reload triggers', () async {
    final realtime = StreamController<RealtimeEvent>.broadcast(sync: true);
    final repository = _FakeConversationRepository([
      _page(unread: 0, preview: '原消息'),
      _page(unread: 1, preview: '最终消息'),
    ]);
    final controller = ConversationListController(repository, realtime.stream);

    await _waitFor(
      () =>
          controller.state.items.isNotEmpty &&
          controller.state.items.single.lastMessage?.preview == '原消息',
    );
    for (var index = 0; index < 5; index++) {
      realtime.add(
        RealtimeEvent(
          name: 'message.created',
          cursor: '5$index-0',
          payload: const {'conversationId': 'conversation-1'},
        ),
      );
    }
    await _waitFor(
      () => controller.state.items.single.lastMessage?.preview == '最终消息',
    );
    await Future<void>.delayed(const Duration(milliseconds: 160));

    expect(repository.loadCount, 2);
    expect(controller.state.items.single.lastMessage?.preview, '最终消息');

    controller.dispose();
    await realtime.close();
  });
}

ConversationListPage _page({required int unread, required String preview}) {
  return ConversationListPage(
    navigationUnread: unread,
    hasMore: false,
    items: [
      ConversationSummary(
        conversationId: 'conversation-1',
        title: '测试好友',
        unread: ConversationUnread(
          count: unread,
          appearance: unread == 0 ? 'none' : 'red',
        ),
        notificationMode: 'normal',
        pinned: false,
        lastMessage: ConversationPreview(
          messageId: 'message-$unread',
          sequence: unread + 1,
          preview: preview,
          createdAt: DateTime.utc(2026, 7, 30),
        ),
      ),
    ],
  );
}

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 80; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('condition was not reached');
}

class _FakeConversationRepository implements ConversationRepository {
  _FakeConversationRepository(this.pages);

  final List<ConversationListPage> pages;
  int loadCount = 0;

  @override
  Future<ConversationListPage> loadConversations() async {
    final page = pages[loadCount];
    loadCount += 1;
    return page;
  }

  @override
  Future<DirectMessagePage> loadMessages(String conversationId) {
    throw UnimplementedError();
  }

  @override
  Future<void> markRead(String conversationId, int lastReadSequence) {
    throw UnimplementedError();
  }

  @override
  Future<DirectMessage> sendText(String conversationId, String text) {
    throw UnimplementedError();
  }
}
