import 'package:fangyuanli_mobile/src/features/friends/data/relationship_repository.dart';
import 'package:fangyuanli_mobile/src/features/friends/domain/friend_models.dart';
import 'package:fangyuanli_mobile/src/features/profile/presentation/my_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _BlockRepository implements RelationshipRepository {
  var blocked = true;

  BlockedUser get blockedUser => const BlockedUser(
    target: UserSummary(userId: 'friend-1', displayName: '周末有空'),
    state: BlockState.blocked,
    priorRelation: PriorRelation.friend,
    directMessagingAllowed: false,
  );

  @override
  Future<BlockedUser> blockUser(String targetUserId) {
    throw UnimplementedError();
  }

  @override
  Future<void> deleteFriend(String friendUserId) {
    throw UnimplementedError();
  }

  @override
  Future<FriendDecision> decide({
    required String requestId,
    required bool accept,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<PageResult<BlockedUser>> loadBlocks() async {
    return PageResult(items: blocked ? [blockedUser] : [], hasMore: false);
  }

  @override
  Future<PageResult<FriendContact>> loadFriends() async {
    return PageResult(
      items: blocked
          ? []
          : const [
              FriendContact(
                userId: 'friend-1',
                displayName: '周末有空',
                nickname: '周末有空',
                canViewMyPosts: true,
                pinned: false,
                directConversationId: 'conversation-1',
              ),
            ],
      hasMore: false,
    );
  }

  @override
  Future<PageResult<FriendRequest>> loadReceivedRequests() async {
    return const PageResult(items: [], hasMore: false);
  }

  @override
  Future<BlockedUser> unblockUser(String targetUserId) async {
    blocked = false;
    return const BlockedUser(
      target: UserSummary(userId: 'friend-1', displayName: '周末有空'),
      state: BlockState.unblocked,
      priorRelation: PriorRelation.friend,
      restoredRelation: PriorRelation.friend,
      directMessagingAllowed: true,
    );
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

void main() {
  testWidgets('从账号与安全进入黑名单，解除后恢复好友关系', (tester) async {
    final repository = _BlockRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          relationshipRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: AccountSecurityScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('黑名单'));
    await tester.pumpAndSettle();
    expect(find.text('周末有空'), findsOneWidget);
    expect(find.text('原好友关系'), findsOneWidget);

    await tester.tap(find.text('移出'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '移出'));
    await tester.pumpAndSettle();

    expect(find.text('黑名单为空'), findsOneWidget);
    expect(find.text('已移出黑名单并恢复好友关系'), findsOneWidget);
    expect(repository.blocked, isFalse);
  });
}
