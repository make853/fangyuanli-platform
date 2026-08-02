import 'dart:async';

import 'package:fangyuanli_mobile/src/core/realtime/realtime_event.dart';
import 'package:fangyuanli_mobile/src/features/friends/application/friends_controller.dart';
import 'package:fangyuanli_mobile/src/features/friends/data/friends_snapshot_store.dart';
import 'package:fangyuanli_mobile/src/features/friends/data/relationship_repository.dart';
import 'package:fangyuanli_mobile/src/features/friends/domain/friend_models.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRelationshipRepository implements RelationshipRepository {
  _FakeRelationshipRepository({required this.request});

  FriendRequest request;
  bool accepted = false;
  String? remarkName;
  bool canViewMyPosts = true;
  bool pinned = false;
  final blockedUsers = <BlockedUser>[];
  int loadFriendsCount = 0;
  int profileVersion = 1;

  @override
  Future<BlockedUser> blockUser(String targetUserId) async {
    final blocked = BlockedUser(
      target: const UserSummary(userId: 'remote-user', displayName: '远山'),
      state: BlockState.blocked,
      priorRelation: accepted ? PriorRelation.friend : PriorRelation.stranger,
      directMessagingAllowed: false,
    );
    accepted = false;
    blockedUsers
      ..removeWhere((item) => item.target.userId == targetUserId)
      ..insert(0, blocked);
    return blocked;
  }

  @override
  Future<void> deleteFriend(String friendUserId) async {
    accepted = false;
  }

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
    loadFriendsCount += 1;
    return PageResult(
      items: accepted
          ? [
              FriendContact(
                userId: 'remote-user',
                displayName: '远山',
                nickname: '远山',
                remarkName: remarkName,
                canViewMyPosts: canViewMyPosts,
                pinned: pinned,
                directConversationId: 'conversation-1',
                profileVersion: profileVersion,
              ),
            ]
          : const [],
      hasMore: false,
    );
  }

  @override
  Future<PageResult<BlockedUser>> loadBlocks() async {
    return PageResult(items: List.of(blockedUsers), hasMore: false);
  }

  @override
  Future<PageResult<FriendRequest>> loadReceivedRequests() async {
    return PageResult(items: [request], hasMore: false);
  }

  @override
  Future<BlockedUser> unblockUser(String targetUserId) async {
    final previous = blockedUsers.singleWhere(
      (item) => item.target.userId == targetUserId,
    );
    blockedUsers.remove(previous);
    accepted = previous.priorRelation == PriorRelation.friend;
    return BlockedUser(
      target: previous.target,
      state: BlockState.unblocked,
      priorRelation: previous.priorRelation,
      restoredRelation: previous.priorRelation,
      directMessagingAllowed: accepted,
    );
  }

  @override
  Future<FriendSettings> updateFriendSettings({
    required String friendUserId,
    String? remarkName,
    bool clearRemark = false,
    bool? canViewMyPosts,
    bool? pinned,
  }) async {
    if (clearRemark) {
      this.remarkName = null;
    } else if (remarkName != null) {
      this.remarkName = remarkName;
    }
    this.canViewMyPosts = canViewMyPosts ?? this.canViewMyPosts;
    this.pinned = pinned ?? this.pinned;
    return FriendSettings(
      friendUserId: friendUserId,
      remarkName: this.remarkName,
      canViewMyPosts: this.canViewMyPosts,
      pinned: this.pinned,
    );
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

  test('备注、权限和置顶更新后立即反映在联系人状态', () async {
    final repository = _FakeRelationshipRepository(request: pendingRequest)
      ..accepted = true;
    final controller = FriendsController(repository);
    await controller.load();

    expect(await controller.updateRemark('remote-user', '小远'), isTrue);
    expect(await controller.updatePostPermission('remote-user', false), isTrue);
    expect(await controller.updatePinned('remote-user', true), isTrue);

    final contact = controller.state.contacts.single;
    expect(contact.visibleName, '小远');
    expect(contact.canViewMyPosts, isFalse);
    expect(contact.pinned, isTrue);
  });

  test('拉黑后移出联系人，解除后恢复原好友关系', () async {
    final repository = _FakeRelationshipRepository(request: pendingRequest)
      ..accepted = true;
    final controller = FriendsController(repository);
    await controller.load();

    expect(await controller.blockUser('remote-user'), isTrue);
    expect(controller.state.contacts, isEmpty);
    expect(
      controller.state.blockedUsers.single.priorRelation,
      PriorRelation.friend,
    );

    expect(await controller.unblockUser('remote-user'), isTrue);
    expect(controller.state.blockedUsers, isEmpty);
    expect(controller.state.contacts.single.userId, 'remote-user');
  });

  test('好友资料版本事件会静默刷新联系人摘要', () async {
    final realtime = StreamController<RealtimeEvent>.broadcast();
    final repository = _FakeRelationshipRepository(request: pendingRequest)
      ..accepted = true;
    final controller = FriendsController(
      repository,
      realtimeEvents: realtime.stream,
    );
    await _waitFor(() => controller.state.contacts.isNotEmpty);
    final initialLoadCount = repository.loadFriendsCount;
    repository.profileVersion = 2;

    realtime.add(
      const RealtimeEvent(
        name: 'profile.updated',
        payload: {'userId': 'remote-user', 'profileVersion': 2},
      ),
    );

    await _waitFor(
      () =>
          repository.loadFriendsCount > initialLoadCount &&
          controller.state.contacts.single.profileVersion == 2,
    );
    controller.dispose();
    await realtime.close();
  });

  test('冷启动先显示本地好友，再静默替换服务器快照', () async {
    final cached = FriendContact(
      userId: 'remote-user',
      displayName: 'Bb',
      nickname: 'Bb',
      canViewMyPosts: true,
      pinned: false,
      directConversationId: 'conversation-1',
    );
    final store = _MemoryFriendsSnapshotStore(
      FriendsSnapshot(
        requests: const [],
        contacts: [cached],
        blockedUsers: const [],
      ),
    );
    final repository = _DelayedRelationshipRepository();
    final controller = FriendsController(
      repository,
      snapshotStore: store,
      ownerUserId: 'owner-a',
    );

    await _waitFor(() => controller.state.contacts.isNotEmpty);
    expect(controller.state.contacts.single.displayName, 'Bb');
    expect(controller.state.isLoading, isFalse);

    repository.complete();
    await _waitFor(() => controller.state.contacts.single.profileVersion == 2);
    expect(store.lastWritten?.contacts.single.profileVersion, 2);
    expect(store.lastOwnerUserId, 'owner-a');

    controller.dispose();
  });
}

class _DelayedRelationshipRepository implements RelationshipRepository {
  final _gate = Completer<void>();

  void complete() => _gate.complete();

  @override
  Future<PageResult<FriendRequest>> loadReceivedRequests() async {
    await _gate.future;
    return const PageResult(items: [], hasMore: false);
  }

  @override
  Future<PageResult<FriendContact>> loadFriends() async {
    await _gate.future;
    return PageResult(
      items: [
        FriendContact(
          userId: 'remote-user',
          displayName: 'Bb',
          nickname: 'Bb',
          canViewMyPosts: true,
          pinned: false,
          directConversationId: 'conversation-1',
          profileVersion: 2,
        ),
      ],
      hasMore: false,
    );
  }

  @override
  Future<PageResult<BlockedUser>> loadBlocks() async {
    await _gate.future;
    return const PageResult(items: [], hasMore: false);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemoryFriendsSnapshotStore implements FriendsSnapshotStore {
  _MemoryFriendsSnapshotStore(this.snapshot);

  final FriendsSnapshot? snapshot;
  FriendsSnapshot? lastWritten;
  String? lastOwnerUserId;

  @override
  Future<FriendsSnapshot?> read(String ownerUserId) async => snapshot;

  @override
  Future<void> write(String ownerUserId, FriendsSnapshot snapshot) async {
    lastOwnerUserId = ownerUserId;
    lastWritten = snapshot;
  }
}

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 400; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('condition was not reached');
}
