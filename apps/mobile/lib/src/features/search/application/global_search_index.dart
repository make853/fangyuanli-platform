import '../../conversations/domain/conversation_summary.dart';
import '../../friends/domain/friend_models.dart';
import '../domain/global_search_models.dart';

class GlobalSearchIndex {
  const GlobalSearchIndex({this.previewLimit = 3});

  final int previewLimit;

  List<GlobalSearchGroup> search({
    required String query,
    required List<FriendContact> contacts,
    required List<ConversationSummary> conversations,
  }) {
    final keyword = normalizeSearchText(query);
    if (keyword.isEmpty) return const [];

    final friends = [
      for (final contact in contacts)
        if (_matchesFriend(contact, keyword))
          GlobalSearchItem(
            category: GlobalSearchCategory.friends,
            id: contact.userId,
            title: contact.visibleName,
            subtitle: contact.remarkName == null
                ? '好友'
                : '好友 · 昵称 ${contact.displayName}',
            conversationId: contact.directConversationId,
          ),
    ];
    final directMessages = [
      for (final conversation in conversations)
        if (_matchesConversation(conversation, keyword))
          GlobalSearchItem(
            category: GlobalSearchCategory.directMessages,
            id:
                conversation.lastMessage?.messageId ??
                conversation.conversationId,
            title: conversation.title,
            subtitle: conversation.lastMessage?.preview ?? '',
            conversationId: conversation.conversationId,
            messageSequence: conversation.lastMessage?.sequence,
          ),
    ];
    final systems = [
      for (final item in _systemItems)
        if (_matches('${item.title} ${item.subtitle}', keyword)) item,
    ];

    return [
      _group(GlobalSearchCategory.friends, friends),
      _group(GlobalSearchCategory.directMessages, directMessages),
      _group(GlobalSearchCategory.systemConversations, systems),
    ].where((group) => group.totalCount > 0).toList(growable: false);
  }

  bool _matchesFriend(FriendContact contact, String keyword) {
    return _matches(
      '${contact.visibleName} ${contact.displayName} ${contact.nickname} ${contact.remarkName ?? ''}',
      keyword,
    );
  }

  bool _matchesConversation(ConversationSummary conversation, String keyword) {
    final preview = conversation.lastMessage?.preview ?? '';
    return _matches(preview, keyword);
  }

  bool _matches(String source, String keyword) {
    return normalizeSearchText(source).contains(keyword);
  }

  GlobalSearchGroup _group(
    GlobalSearchCategory category,
    List<GlobalSearchItem> items,
  ) {
    return GlobalSearchGroup(
      category: category,
      items: items.take(previewLimit).toList(growable: false),
      totalCount: items.length,
    );
  }

  static const _systemItems = [
    GlobalSearchItem(
      category: GlobalSearchCategory.systemConversations,
      id: 'friend_requests',
      title: '好友申请',
      subtitle: '新的好友申请与处理记录',
    ),
    GlobalSearchItem(
      category: GlobalSearchCategory.systemConversations,
      id: 'activity_notifications',
      title: '活动通知',
      subtitle: '报名、审批和活动变更',
    ),
    GlobalSearchItem(
      category: GlobalSearchCategory.systemConversations,
      id: 'post_notifications',
      title: '动态通知',
      subtitle: '点赞、评论和回复',
    ),
    GlobalSearchItem(
      category: GlobalSearchCategory.systemConversations,
      id: 'activity_expectations',
      title: '发现期待活动',
      subtitle: '符合爱好和关键词的活动',
    ),
  ];
}

String normalizeSearchText(String value) {
  return value.toLowerCase().replaceAll(RegExp(r'\s+'), '');
}
