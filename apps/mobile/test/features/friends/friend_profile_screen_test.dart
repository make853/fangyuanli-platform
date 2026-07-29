import 'package:fangyuanli_mobile/src/features/friends/data/relationship_repository.dart';
import 'package:fangyuanli_mobile/src/features/friends/domain/friend_models.dart';
import 'package:fangyuanli_mobile/src/features/friends/presentation/friends_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _ProfileRepository implements RelationshipRepository {
  String? remarkName;
  bool canViewMyPosts = true;
  bool pinned = false;
  bool isFriend = true;
  final blocks = <BlockedUser>[];

  FriendContact get contact => FriendContact(
    userId: 'friend-1',
    displayName: '阿禾',
    nickname: '阿禾',
    remarkName: remarkName,
    canViewMyPosts: canViewMyPosts,
    pinned: pinned,
    directConversationId: 'conversation-1',
  );

  @override
  Future<BlockedUser> blockUser(String targetUserId) async {
    isFriend = false;
    final block = BlockedUser(
      target: const UserSummary(userId: 'friend-1', displayName: '阿禾'),
      state: BlockState.blocked,
      priorRelation: PriorRelation.friend,
      directMessagingAllowed: false,
    );
    blocks.add(block);
    return block;
  }

  @override
  Future<void> deleteFriend(String friendUserId) async => isFriend = false;

  @override
  Future<FriendDecision> decide({
    required String requestId,
    required bool accept,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<PageResult<BlockedUser>> loadBlocks() async {
    return PageResult(items: List.of(blocks), hasMore: false);
  }

  @override
  Future<PageResult<FriendContact>> loadFriends() async {
    return PageResult(items: isFriend ? [contact] : [], hasMore: false);
  }

  @override
  Future<PageResult<FriendRequest>> loadReceivedRequests() async {
    return const PageResult(items: [], hasMore: false);
  }

  @override
  Future<BlockedUser> unblockUser(String targetUserId) async {
    final previous = blocks.removeLast();
    isFriend = true;
    return BlockedUser(
      target: previous.target,
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
  }) async {
    this.remarkName = clearRemark ? null : remarkName ?? this.remarkName;
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
  testWidgets('从联系人进入资料页修改备注，返回后联系人同步更新', (tester) async {
    final repository = _ProfileRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          relationshipRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: Scaffold(body: FriendsScreen())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('联系人'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('阿禾'));
    await tester.pumpAndSettle();
    expect(find.text('好友资料'), findsOneWidget);

    await tester.tap(find.text('编辑备注'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '123');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('123'), findsWidgets);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('123'), findsOneWidget);
    expect(find.text('昵称：阿禾'), findsOneWidget);
  });

  testWidgets('拉黑好友后返回联系人空状态且操作有反馈', (tester) async {
    final repository = _ProfileRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          relationshipRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: Scaffold(body: FriendsScreen())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('联系人'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('阿禾'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('加入黑名单'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '加入黑名单'));
    await tester.pumpAndSettle();

    expect(find.text('还没有好友'), findsOneWidget);
    expect(find.text('已加入黑名单'), findsOneWidget);
  });
}
