import 'package:fangyuanli_mobile/src/features/friends/data/relationship_repository.dart';
import 'package:fangyuanli_mobile/src/features/friends/domain/friend_models.dart';
import 'package:fangyuanli_mobile/src/features/friends/presentation/friends_screen.dart';
import 'package:fangyuanli_mobile/src/features/media/domain/media_upload_models.dart';
import 'package:fangyuanli_mobile/src/features/profile/data/profile_repository.dart';
import 'package:fangyuanli_mobile/src/features/profile/domain/profile_models.dart';
import 'package:fangyuanli_mobile/src/features/profile/presentation/profile_media_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _RelationshipRepository implements RelationshipRepository {
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

class _UserProfileRepository implements ProfileRepository {
  static const _relationship = ProfileRelationship(
    state: ProfileRelationshipState.friend,
    canStartDirectChat: true,
    isBlockedByMe: false,
    hasBlockedMe: false,
    canViewMyPosts: true,
  );

  final profile = const UserProfile(
    userId: 'friend-1',
    displayName: '阿禾',
    fangyuanNumber: 'FYTESTFRIEND',
    nickname: '阿禾',
    gender: ProfileGender.female,
    signature: '周末去打羽毛球',
    visibility: ProfileVisibility.full,
    profileVersion: 1,
    relationship: _relationship,
    allowedActions: [],
    avatar: MediaAsset(mediaId: 'avatar-1', status: 'ready'),
    background: MediaAsset(mediaId: 'background-1', status: 'ready'),
  );

  @override
  Future<UserProfile> loadMine() async => profile;

  @override
  Future<UserProfile> loadUser(String userId) async => profile;

  @override
  Future<PrivacySettings> loadPrivacy() async => PrivacySettings(
    strangersCanViewProfile: true,
    searchableByFangyuanNumber: true,
    globalGroupMuted: false,
    updatedAt: DateTime(2026, 8, 2),
  );

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
  testWidgets('从联系人进入资料页修改备注，返回后联系人同步更新', (tester) async {
    final repository = _RelationshipRepository();
    final profiles = _UserProfileRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          relationshipRepositoryProvider.overrideWithValue(repository),
          profileRepositoryProvider.overrideWithValue(profiles),
        ],
        child: const MaterialApp(home: Scaffold(body: FriendsScreen())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('联系人'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('阿禾'));
    await tester.pumpAndSettle();
    expect(find.text('个人资料'), findsOneWidget);
    expect(find.text('周末去打羽毛球'), findsOneWidget);
    expect(
      tester
          .widget<ProfileAvatarImage>(find.byType(ProfileAvatarImage))
          .media
          ?.mediaId,
      'avatar-1',
    );
    expect(
      tester
          .widget<ProfileBackgroundImage>(find.byType(ProfileBackgroundImage))
          .media
          ?.mediaId,
      'background-1',
    );

    await tester.tap(find.byTooltip('好友设置'));
    await tester.pumpAndSettle();
    expect(find.text('好友设置'), findsOneWidget);

    await tester.tap(find.text('编辑备注'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '123');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('123'), findsWidgets);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('个人资料'), findsOneWidget);
    expect(find.text('123'), findsOneWidget);
    expect(find.text('阿禾'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('123'), findsOneWidget);
    expect(find.text('昵称：阿禾'), findsOneWidget);
  });

  testWidgets('拉黑好友后返回联系人空状态且操作有反馈', (tester) async {
    final repository = _RelationshipRepository();
    final profiles = _UserProfileRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          relationshipRepositoryProvider.overrideWithValue(repository),
          profileRepositoryProvider.overrideWithValue(profiles),
        ],
        child: const MaterialApp(home: Scaffold(body: FriendsScreen())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('联系人'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('阿禾'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('好友设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('加入黑名单'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '加入黑名单'));
    await tester.pumpAndSettle();

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('还没有好友'), findsOneWidget);
    expect(find.text('已加入黑名单'), findsOneWidget);
  });
}
