import 'package:fangyuanli_mobile/src/features/conversations/domain/conversation_summary.dart';
import 'package:fangyuanli_mobile/src/features/friends/domain/friend_models.dart';
import 'package:fangyuanli_mobile/src/features/search/application/global_search_index.dart';
import 'package:fangyuanli_mobile/src/features/search/domain/global_search_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('不同类别独立连续子串匹配，不召回无关好友', () {
    final groups = const GlobalSearchIndex().search(
      query: '羽毛球',
      contacts: const [
        FriendContact(
          userId: 'friend-1',
          displayName: '林间小路',
          nickname: '林间小路',
          canViewMyPosts: true,
          pinned: false,
          directConversationId: 'conversation-1',
        ),
      ],
      conversations: [_conversation(title: '小桃子', preview: '周六一起打羽毛球')],
    );

    expect(groups.map((group) => group.category), [
      GlobalSearchCategory.directMessages,
    ]);
    expect(groups.single.items.single.subtitle, '周六一起打羽毛球');
  });

  test('系统会话可搜索且单类预览最多三条', () {
    final systemGroups = const GlobalSearchIndex().search(
      query: '好友申请',
      contacts: const [],
      conversations: const [],
    );
    expect(systemGroups.single.items.single.title, '好友申请');

    final friendGroups = const GlobalSearchIndex().search(
      query: '桃',
      contacts: [
        for (var index = 0; index < 4; index++)
          FriendContact(
            userId: 'friend-$index',
            displayName: '桃子$index',
            nickname: '桃子$index',
            canViewMyPosts: true,
            pinned: false,
            directConversationId: 'conversation-$index',
          ),
      ],
      conversations: const [],
    );
    expect(friendGroups.single.items, hasLength(3));
    expect(friendGroups.single.totalCount, 4);
    expect(friendGroups.single.hasMore, isTrue);
  });
}

ConversationSummary _conversation({
  required String title,
  required String preview,
}) {
  return ConversationSummary(
    conversationId: 'conversation-1',
    title: title,
    unread: const ConversationUnread(count: 0, appearance: 'none'),
    notificationMode: 'normal',
    pinned: false,
    lastMessage: ConversationPreview(
      messageId: 'message-1',
      sequence: 1,
      preview: preview,
      createdAt: DateTime(2026, 8, 2),
    ),
  );
}
