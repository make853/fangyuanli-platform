import 'package:fangyuanli_mobile/src/features/friends/application/friends_controller.dart';
import 'package:fangyuanli_mobile/src/features/friends/data/relationship_repository.dart';
import 'package:fangyuanli_mobile/src/features/friends/domain/friend_models.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRelationshipRepository implements RelationshipRepository {
  _FakeRelationshipRepository({required this.request});

  FriendRequest request;
  bool accepted = false;

  @override
  Future<FriendDecision> decide({
    required String requestId,
    required bool accept,
  }) async {
    request = FriendRequest(
      requestId: request.requestId,
      sender: request.sender,
      receiver: request.receiver,
      status: accept
          ? FriendRequestStatus.accepted
          : FriendRequestStatus.rejected,
      applicationNote: request.applicationNote,
      createdAt: request.createdAt,
      decidedAt: DateTime(2026, 7, 29, 18),
    );
    accepted = accept;
    return FriendDecision(
      request: request,
      friendshipId: accept ? 'friendship-1' : null,
      friendUserId: accept ? request.sender.userId : null,
      directConversationId: accept ? 'conversation-1' : null,
    );
  }

  @override
  Future<PageResult<FriendContact>> loadFriends() async {
    return PageResult(
      items: accepted
          ? const [
              FriendContact(
                userId: 'remote-user',
                displayName: '远山',
                nickname: '远山',
                canViewMyPosts: true,
                pinned: false,
                directConversationId: 'conversation-1',
              ),
            ]
          : const [],
      hasMore: false,
    );
  }

  @override
  Future<PageResult<FriendRequest>> loadReceivedRequests() async {
    return PageResult(items: [request], hasMore: false);
  }
}

void main() {
  late FriendRequest pendingRequest;

  setUp(() {
    pendingRequest = FriendRequest(
      requestId: 'request-1',
      sender: const UserSummary(userId: 'remote-user', displayName: '远山'),
      receiver: const UserSummary(userId: 'local-user', displayName: '小方'),
      status: FriendRequestStatus.pending,
      applicationNote: '一起参加附近活动',
      createdAt: DateTime(2026, 7, 29, 17),
    );
  });

  test('同意后申请记录保留已同意状态并同步联系人', () async {
    final repository = _FakeRelationshipRepository(request: pendingRequest);
    final controller = FriendsController(repository);
    await controller.load();

    final succeeded = await controller.decide(
      requestId: pendingRequest.requestId,
      accept: true,
    );

    expect(succeeded, isTrue);
    expect(controller.state.requests, hasLength(1));
    expect(
      controller.state.requests.single.status,
      FriendRequestStatus.accepted,
    );
    expect(controller.state.pendingRequestCount, 0);
    expect(controller.state.contacts.single.visibleName, '远山');
  });

  test('拒绝后申请记录保留已拒绝状态且不创建联系人', () async {
    final repository = _FakeRelationshipRepository(request: pendingRequest);
    final controller = FriendsController(repository);
    await controller.load();

    final succeeded = await controller.decide(
      requestId: pendingRequest.requestId,
      accept: false,
    );

    expect(succeeded, isTrue);
    expect(
      controller.state.requests.single.status,
      FriendRequestStatus.rejected,
    );
    expect(controller.state.contacts, isEmpty);
  });
}
