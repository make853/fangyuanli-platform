import 'package:fangyuanli_mobile/src/features/friends/data/relationship_repository.dart';
import 'package:fangyuanli_mobile/src/features/friends/domain/friend_models.dart';
import 'package:fangyuanli_mobile/src/features/friends/presentation/friends_screen.dart';
import 'package:fangyuanli_mobile/src/features/profile/data/profile_repository.dart';
import 'package:fangyuanli_mobile/src/features/profile/domain/profile_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRelationshipRepository implements RelationshipRepository {
  var status = FriendRequestStatus.pending;

  @override
  Future<BlockedUser> blockUser(String targetUserId) {
    throw UnimplementedError();
  }

  @override
  Future<void> deleteFriend(String friendUserId) {
    throw UnimplementedError();
  }

  FriendRequest get request => FriendRequest(
    requestId: 'request-1',
    sender: const UserSummary(userId: 'remote-user', displayName: '远山'),
    receiver: const UserSummary(userId: 'local-user', displayName: '小方'),
    status: status,
    applicationNote: '想和你一起参加附近活动',
    createdAt: DateTime(2026, 7, 29, 17),
  );

  @override
  Future<FriendDecision> decide({
    required String requestId,
    required bool accept,
  }) async {
    status = accept
        ? FriendRequestStatus.accepted
        : FriendRequestStatus.rejected;
    return FriendDecision(request: request);
  }

  @override
  Future<PageResult<FriendContact>> loadFriends() async {
    return const PageResult(items: [], hasMore: false);
  }

  @override
  Future<PageResult<BlockedUser>> loadBlocks() async {
    return const PageResult(items: [], hasMore: false);
  }

  @override
  Future<PageResult<FriendRequest>> loadReceivedRequests() async {
    return PageResult(items: [request], hasMore: false);
  }

  @override
  Future<BlockedUser> unblockUser(String targetUserId) {
    throw UnimplementedError();
  }

  @override
  Future<FriendSettings> updateFriendSettings({
    required String friendUserId,
    String? remarkName,
    bool clearRemark = false,
    bool? canViewMyPosts,
    bool? pinned,
  }) {
    throw UnimplementedError();
  }
}

class _FakeProfileRepository implements ProfileRepository {
  @override
  Future<UserProfile> loadUser(String userId) async => const UserProfile(
    userId: 'remote-user',
    displayName: '远山',
    fangyuanNumber: 'FY000000000002',
    nickname: '远山',
    gender: ProfileGender.unspecified,
    signature: '喜欢附近的运动活动',
    visibility: ProfileVisibility.full,
    profileVersion: 1,
    relationship: ProfileRelationship(
      state: ProfileRelationshipState.requestPending,
      canStartDirectChat: false,
      isBlockedByMe: false,
      hasBlockedMe: false,
      canViewMyPosts: false,
    ),
    allowedActions: [],
  );

  @override
  Future<UserProfile> loadMine() => throw UnimplementedError();

  @override
  Future<PrivacySettings> loadPrivacy() => throw UnimplementedError();

  @override
  Future<UserProfile> updateMine({
    required String ownerUserId,
    required int expectedVersion,
    String? nickname,
    ProfileGender? gender,
    String? signature,
    ProfileMediaChange avatar = const ProfileMediaChange.keep(),
    ProfileMediaChange background = const ProfileMediaChange.keep(),
  }) => throw UnimplementedError();

  @override
  Future<PrivacySettings> updatePrivacy({
    bool? strangersCanViewProfile,
    bool? searchableByFangyuanNumber,
    bool? globalGroupMuted,
  }) => throw UnimplementedError();
}

void main() {
  testWidgets('好友申请从消息进入，处理后原记录显示已同意', (tester) async {
    final repository = _FakeRelationshipRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          relationshipRepositoryProvider.overrideWithValue(repository),
          profileRepositoryProvider.overrideWithValue(_FakeProfileRepository()),
        ],
        child: const MaterialApp(home: Scaffold(body: FriendsScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('好友申请'), findsOneWidget);
    expect(find.text('1 条申请等待处理'), findsOneWidget);

    await tester.tap(find.text('好友申请'));
    await tester.pumpAndSettle();
    expect(find.text('想和你一起参加附近活动'), findsOneWidget);

    await tester.tap(find.text('同意'));
    await tester.pumpAndSettle();

    expect(find.text('已同意'), findsOneWidget);
    expect(find.text('想和你一起参加附近活动'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('消息'), findsOneWidget);
    expect(find.text('联系人'), findsOneWidget);
  });

  testWidgets('好友申请头像进入对方资料并按原路径返回申请列表', (tester) async {
    final repository = _FakeRelationshipRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          relationshipRepositoryProvider.overrideWithValue(repository),
          profileRepositoryProvider.overrideWithValue(_FakeProfileRepository()),
        ],
        child: const MaterialApp(home: Scaffold(body: FriendsScreen())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('好友申请'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('friend-request-profile-request-1')),
    );
    await tester.pumpAndSettle();

    expect(find.text('个人资料'), findsOneWidget);
    expect(find.text('远山'), findsWidgets);
    expect(find.text('好友申请处理中'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('好友申请'), findsOneWidget);
    expect(find.text('想和你一起参加附近活动'), findsOneWidget);
    expect(find.text('待处理'), findsOneWidget);
  });
}
