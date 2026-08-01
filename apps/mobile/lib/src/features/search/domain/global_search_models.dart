enum GlobalSearchCategory { friends, directMessages, systemConversations }

class GlobalSearchItem {
  const GlobalSearchItem({
    required this.category,
    required this.id,
    required this.title,
    required this.subtitle,
    this.conversationId,
    this.messageSequence,
  });

  final GlobalSearchCategory category;
  final String id;
  final String title;
  final String subtitle;
  final String? conversationId;
  final int? messageSequence;
}

class GlobalSearchGroup {
  const GlobalSearchGroup({
    required this.category,
    required this.items,
    required this.totalCount,
  });

  final GlobalSearchCategory category;
  final List<GlobalSearchItem> items;
  final int totalCount;

  bool get hasMore => totalCount > items.length;
}
