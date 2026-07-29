import 'package:fangyuanli_mobile/src/features/friends/domain/friend_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('好友申请响应能够解析完整状态和申请说明', () {
    final request = FriendRequest.fromJson({
      'requestId': 'request-1',
      'sender': {'userId': 'remote-user', 'displayName': '远山', 'avatar': null},
      'receiver': {'userId': 'local-user', 'displayName': '小方', 'avatar': null},
      'status': 'accepted',
      'applicationNote': '一起参加附近活动',
      'createdAt': '2026-07-29T09:00:00.000Z',
      'decidedAt': '2026-07-29T09:10:00.000Z',
    });

    expect(request.status, FriendRequestStatus.accepted);
    expect(request.applicationNote, '一起参加附近活动');
    expect(request.sender.displayName, '远山');
    expect(request.decidedAt, isNotNull);
  });

  test('联系人优先显示备注名', () {
    final contact = FriendContact.fromJson({
      'userId': 'remote-user',
      'displayName': '阿禾',
      'nickname': '阿禾',
      'remarkName': '123',
      'canViewMyPosts': true,
      'pinned': true,
      'directConversationId': 'conversation-1',
    });

    expect(contact.visibleName, '123');
    expect(contact.pinned, isTrue);
  });
}
