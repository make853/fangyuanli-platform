import '../../media/domain/media_upload_models.dart';

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

  Map<String, dynamic> toJson() => {
    'count': count,
    'appearance': appearance,
    if (firstUnreadSequence != null) 'firstUnreadSequence': firstUnreadSequence,
  };
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

  Map<String, dynamic> toJson() => {
    'messageId': messageId,
    'sequence': sequence,
    'preview': preview,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };
}

class ConversationSummary {
  const ConversationSummary({
    required this.conversationId,
    required this.title,
    required this.unread,
    required this.notificationMode,
    required this.pinned,
    this.lastMessage,
    this.peerUserId,
    this.profileVersion = 1,
    this.avatar,
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
      peerUserId: json['peerUserId'] as String?,
      profileVersion: json['profileVersion'] as int? ?? 1,
      avatar: _optionalMedia(json['avatar']),
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
  final String? peerUserId;
  final int profileVersion;
  final MediaAsset? avatar;

  Map<String, dynamic> toJson() => {
    'conversationId': conversationId,
    'title': title,
    'unread': unread.toJson(),
    'notificationMode': notificationMode,
    'pinned': pinned,
    if (lastMessage != null) 'lastMessage': lastMessage!.toJson(),
    'peerUserId': peerUserId,
    'profileVersion': profileVersion,
    if (avatar != null) 'avatar': avatar!.toJson(),
  };

  ConversationSummary copyWith({String? title, bool? pinned}) {
    return ConversationSummary(
      conversationId: conversationId,
      title: title ?? this.title,
      unread: unread,
      notificationMode: notificationMode,
      pinned: pinned ?? this.pinned,
      lastMessage: lastMessage,
      peerUserId: peerUserId,
      profileVersion: profileVersion,
      avatar: avatar,
    );
  }
}

MediaAsset? _optionalMedia(Object? value) =>
    value is Map ? MediaAsset.fromJson(Map<String, dynamic>.from(value)) : null;

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
