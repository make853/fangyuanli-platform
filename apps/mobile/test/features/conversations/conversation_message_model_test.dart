import 'package:fangyuanli_mobile/src/features/conversations/domain/conversation_message.dart';
import 'package:fangyuanli_mobile/src/features/media/domain/media_upload_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('message cache payload round-trips identity and signed avatar', () {
    final message = ConversationMessage(
      messageId: 'message-1',
      conversationId: 'conversation-1',
      sequence: 42,
      senderUserId: 'user-b',
      senderName: '小桃子',
      text: '附近见',
      createdAt: DateTime.utc(2026, 8, 2, 10, 30),
      deliveryState: 'sent',
      senderProfileVersion: 5,
      senderAvatar: MediaAsset(
        mediaId: 'media-avatar',
        status: 'ready',
        mediaType: 'image',
        thumbnailUrl: Uri.parse('https://example.test/avatar-thumb'),
        expiresAt: DateTime.utc(2026, 8, 2, 10, 40),
      ),
    );

    final restored = ConversationMessage.fromJson(message.toJson());

    expect(restored.messageId, message.messageId);
    expect(restored.sequence, 42);
    expect(restored.senderName, '小桃子');
    expect(restored.senderProfileVersion, 5);
    expect(
      restored.senderAvatar?.thumbnailUrl,
      Uri.parse('https://example.test/avatar-thumb'),
    );
    expect(restored.createdAt.toUtc(), message.createdAt);
  });

  test('round-trips scene-neutral message payloads without losing fields', () {
    final message = ConversationMessage(
      messageId: 'message-activity',
      clientMessageId: 'client-activity',
      conversationId: 'conversation-activity',
      sequence: 9,
      type: ConversationMessageType.activityCard,
      senderUserId: 'organizer',
      senderName: '组织者',
      text: '周六羽毛球',
      payload: const {'activityId': 'activity-1', 'memberCount': 8},
      media: const [
        MediaAsset(mediaId: 'media-cover', status: 'ready', mediaType: 'image'),
      ],
      replyToMessageId: 'message-parent',
      mentions: const [
        ConversationMessageIdentity(userId: 'user-b', displayName: '小桃子'),
      ],
      createdAt: DateTime.utc(2026, 8, 2, 11),
      expiresAt: DateTime.utc(2026, 9, 2, 11),
      deliveryState: 'sent',
    );

    final restored = ConversationMessage.fromJson(message.toJson());

    expect(restored.type, ConversationMessageType.activityCard);
    expect(restored.clientMessageId, 'client-activity');
    expect(restored.payload?['memberCount'], 8);
    expect(restored.media.single.mediaId, 'media-cover');
    expect(restored.replyToMessageId, 'message-parent');
    expect(restored.mentions.single.displayName, '小桃子');
    expect(restored.expiresAt?.toUtc(), message.expiresAt);
  });
}
