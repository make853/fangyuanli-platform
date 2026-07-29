class DirectMessage {
  const DirectMessage({
    required this.messageId,
    required this.conversationId,
    required this.sequence,
    required this.senderUserId,
    required this.senderName,
    required this.text,
    required this.createdAt,
    required this.deliveryState,
  });

  factory DirectMessage.fromJson(Map<String, dynamic> json) {
    final sender = json['sender'];
    final senderMap = sender is Map
        ? Map<String, dynamic>.from(sender)
        : const <String, dynamic>{};
    return DirectMessage(
      messageId: json['messageId'] as String,
      conversationId: json['conversationId'] as String,
      sequence: json['sequence'] as int,
      senderUserId: senderMap['userId'] as String?,
      senderName: senderMap['displayName'] as String? ?? '已注销用户',
      text: json['text'] as String? ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
      deliveryState: json['deliveryState'] as String? ?? 'sent',
    );
  }

  final String messageId;
  final String conversationId;
  final int sequence;
  final String? senderUserId;
  final String senderName;
  final String text;
  final DateTime createdAt;
  final String deliveryState;
}

class DirectMessagePage {
  const DirectMessagePage({
    required this.items,
    required this.hasEarlier,
    required this.hasLater,
  });

  final List<DirectMessage> items;
  final bool hasEarlier;
  final bool hasLater;
}
