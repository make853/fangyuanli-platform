import '../../media/domain/media_upload_models.dart';

enum ConversationMessageType {
  text('text'),
  image('image'),
  voice('voice'),
  video('video'),
  sticker('sticker'),
  location('location'),
  liveLocation('liveLocation'),
  activityCard('activityCard'),
  systemEvent('systemEvent');

  const ConversationMessageType(this.wireValue);

  final String wireValue;

  static ConversationMessageType fromWire(Object? value) {
    if (value is! String) {
      throw const FormatException('消息缺少类型');
    }
    return values.firstWhere(
      (type) => type.wireValue == value,
      orElse: () => throw FormatException('未知的消息类型：$value'),
    );
  }
}

class ConversationMessageIdentity {
  const ConversationMessageIdentity({
    required this.userId,
    required this.displayName,
    this.profileVersion = 1,
    this.avatar,
  });

  factory ConversationMessageIdentity.fromJson(Map<String, dynamic> json) {
    return ConversationMessageIdentity(
      userId: json['userId'] as String?,
      displayName: json['displayName'] as String? ?? '已注销用户',
      profileVersion: json['profileVersion'] as int? ?? 1,
      avatar: _optionalMedia(json['avatar']),
    );
  }

  final String? userId;
  final String displayName;
  final int profileVersion;
  final MediaAsset? avatar;

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'displayName': displayName,
    'profileVersion': profileVersion,
    if (avatar != null) 'avatar': avatar!.toJson(),
  };
}

/// Scene-neutral message model shared by direct, plaza, place, activity and
/// system conversations. Scene permissions do not belong in this model.
class ConversationMessage {
  const ConversationMessage({
    required this.messageId,
    required this.conversationId,
    required this.sequence,
    this.type = ConversationMessageType.text,
    required this.createdAt,
    required this.deliveryState,
    this.clientMessageId,
    this.senderUserId,
    this.senderName = '系统消息',
    this.senderProfileVersion = 1,
    this.senderAvatar,
    this.text,
    this.payload,
    this.media = const [],
    this.replyToMessageId,
    this.mentions = const [],
    this.expiresAt,
  });

  factory ConversationMessage.fromJson(Map<String, dynamic> json) {
    final sender = json['sender'];
    final rawMedia = json['media'];
    final rawMentions = json['mentions'];
    final payload = json['payload'];
    return ConversationMessage(
      messageId: json['messageId'] as String,
      clientMessageId: json['clientMessageId'] as String?,
      conversationId: json['conversationId'] as String,
      sequence: json['sequence'] as int,
      senderUserId: sender is Map ? sender['userId'] as String? : null,
      senderName: sender is Map
          ? sender['displayName'] as String? ?? '已注销用户'
          : '系统消息',
      senderProfileVersion: sender is Map
          ? sender['profileVersion'] as int? ?? 1
          : 1,
      senderAvatar: sender is Map ? _optionalMedia(sender['avatar']) : null,
      type: ConversationMessageType.fromWire(json['type'] ?? 'text'),
      text: json['text'] as String?,
      payload: payload is Map ? Map<String, dynamic>.from(payload) : null,
      media: rawMedia is List
          ? [
              for (final item in rawMedia)
                if (item is Map)
                  MediaAsset.fromJson(Map<String, dynamic>.from(item)),
            ]
          : const [],
      replyToMessageId: json['replyToMessageId'] as String?,
      mentions: rawMentions is List
          ? [
              for (final item in rawMentions)
                if (item is Map)
                  ConversationMessageIdentity.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
            ]
          : const [],
      deliveryState: json['deliveryState'] as String? ?? 'sent',
      createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
      expiresAt: _optionalDateTime(json['expiresAt']),
    );
  }

  final String messageId;
  final String? clientMessageId;
  final String conversationId;
  final int sequence;
  final String? senderUserId;
  final String senderName;
  final int senderProfileVersion;
  final MediaAsset? senderAvatar;
  final ConversationMessageType type;
  final String? text;
  final Map<String, dynamic>? payload;
  final List<MediaAsset> media;
  final String? replyToMessageId;
  final List<ConversationMessageIdentity> mentions;
  final String deliveryState;
  final DateTime createdAt;
  final DateTime? expiresAt;

  bool get isPending => deliveryState == 'sending' || deliveryState == 'failed';

  ConversationMessage copyWith({
    String? messageId,
    String? clientMessageId,
    int? sequence,
    String? deliveryState,
  }) {
    return ConversationMessage(
      messageId: messageId ?? this.messageId,
      clientMessageId: clientMessageId ?? this.clientMessageId,
      conversationId: conversationId,
      sequence: sequence ?? this.sequence,
      senderUserId: senderUserId,
      senderName: senderName,
      senderProfileVersion: senderProfileVersion,
      senderAvatar: senderAvatar,
      type: type,
      text: text,
      payload: payload,
      media: media,
      replyToMessageId: replyToMessageId,
      mentions: mentions,
      deliveryState: deliveryState ?? this.deliveryState,
      createdAt: createdAt,
      expiresAt: expiresAt,
    );
  }

  String get previewText => switch (type) {
    ConversationMessageType.text => text ?? '',
    ConversationMessageType.image => '[图片]',
    ConversationMessageType.voice => '[语音]',
    ConversationMessageType.video => '[视频]',
    ConversationMessageType.sticker => '[表情]',
    ConversationMessageType.location => '[位置]',
    ConversationMessageType.liveLocation => '[实时位置]',
    ConversationMessageType.activityCard => text ?? '[活动]',
    ConversationMessageType.systemEvent => text ?? '[系统消息]',
  };

  Map<String, dynamic> toJson() => {
    'messageId': messageId,
    'clientMessageId': clientMessageId,
    'conversationId': conversationId,
    'sequence': sequence,
    'sender': senderUserId == null
        ? null
        : {
            'userId': senderUserId,
            'displayName': senderName,
            'profileVersion': senderProfileVersion,
            if (senderAvatar != null) 'avatar': senderAvatar!.toJson(),
          },
    'type': type.wireValue,
    'text': text,
    'payload': payload,
    'media': [for (final item in media) item.toJson()],
    'replyToMessageId': replyToMessageId,
    'mentions': [for (final item in mentions) item.toJson()],
    'deliveryState': deliveryState,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'expiresAt': expiresAt?.toUtc().toIso8601String(),
  };
}

class ConversationMessagePage {
  const ConversationMessagePage({
    required this.items,
    required this.hasEarlier,
    required this.hasLater,
  });

  final List<ConversationMessage> items;
  final bool hasEarlier;
  final bool hasLater;
}

MediaAsset? _optionalMedia(Object? value) =>
    value is Map ? MediaAsset.fromJson(Map<String, dynamic>.from(value)) : null;

DateTime? _optionalDateTime(Object? value) =>
    value is String && value.isNotEmpty
    ? DateTime.parse(value).toLocal()
    : null;
