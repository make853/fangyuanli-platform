class ConversationUnread {
  const ConversationUnread({
    required this.count,
    required this.appearance,
    this.firstUnreadSequence,
  });

  factory ConversationUnread.fromJson(Map<String, dynamic> json) {
    return ConversationUnread(
      count: json['count'] as int? ?? 0,
      appearance: json['appearance'] as String? ?? 'none',
      firstUnreadSequence: json['firstUnreadSequence'] as int?,
    );
  }

  final int count;
  final String appearance;
  final int? firstUnreadSequence;
}

class ConversationPreview {
  const ConversationPreview({
    required this.messageId,
    required this.sequence,
    required this.preview,
    required this.createdAt,
  });

  factory ConversationPreview.fromJson(Map<String, dynamic> json) {
    return ConversationPreview(
      messageId: json['messageId'] as String,
      sequence: json['sequence'] as int,
      preview: json['preview'] as String? ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
    );
  }

  final String messageId;
  final int sequence;
  final String preview;
  final DateTime createdAt;
}

class ConversationSummary {
  const ConversationSummary({
    required this.conversationId,
    required this.title,
    required this.unread,
    required this.notificationMode,
    required this.pinned,
    this.lastMessage,
  });

  factory ConversationSummary.fromJson(Map<String, dynamic> json) {
    final rawUnread = json['unread'];
    final rawLastMessage = json['lastMessage'];
    return ConversationSummary(
      conversationId: json['conversationId'] as String,
      title: json['title'] as String? ?? '好友',
      unread: ConversationUnread.fromJson(
        rawUnread is Map
            ? Map<String, dynamic>.from(rawUnread)
            : const <String, dynamic>{},
      ),
      notificationMode: json['notificationMode'] as String? ?? 'normal',
      pinned: json['pinned'] as bool? ?? false,
      lastMessage: rawLastMessage is Map
          ? ConversationPreview.fromJson(
              Map<String, dynamic>.from(rawLastMessage),
            )
          : null,
    );
  }

  final String conversationId;
  final String title;
  final ConversationUnread unread;
  final String notificationMode;
  final bool pinned;
  final ConversationPreview? lastMessage;

  ConversationSummary copyWith({String? title, bool? pinned}) {
    return ConversationSummary(
      conversationId: conversationId,
      title: title ?? this.title,
      unread: unread,
      notificationMode: notificationMode,
      pinned: pinned ?? this.pinned,
      lastMessage: lastMessage,
    );
  }
}

class ConversationListPage {
  const ConversationListPage({
    required this.items,
    required this.navigationUnread,
    required this.hasMore,
  });

  final List<ConversationSummary> items;
  final int navigationUnread;
  final bool hasMore;
}
