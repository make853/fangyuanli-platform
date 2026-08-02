import 'package:fangyuanli_mobile/src/features/conversations/domain/direct_message.dart';
import 'package:fangyuanli_mobile/src/features/media/domain/media_upload_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('message cache payload round-trips identity and signed avatar', () {
    final message = DirectMessage(
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

    final restored = DirectMessage.fromJson(message.toJson());

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
}
