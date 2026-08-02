import 'package:fangyuanli_mobile/src/features/profile/data/profile_repository.dart';
import 'package:fangyuanli_mobile/src/features/profile/domain/profile_models.dart';
import 'package:fangyuanli_mobile/src/features/profile/presentation/my_screen.dart';
import 'package:fangyuanli_mobile/src/features/profile/presentation/profile_media_widgets.dart';
import 'package:fangyuanli_mobile/src/features/media/domain/media_upload_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _relationship = ProfileRelationship(
  state: ProfileRelationshipState.self,
  canStartDirectChat: false,
  isBlockedByMe: false,
  hasBlockedMe: false,
  canViewMyPosts: false,
);

class _ProfileRepository implements ProfileRepository {
  UserProfile profile = const UserProfile(
    userId: '019f0000-0000-7000-8000-00000000000a',
    displayName: '小桃子',
    fangyuanNumber: 'FY000000000001',
    nickname: '小桃子',
    gender: ProfileGender.unspecified,
    signature: '今天也要开心',
    visibility: ProfileVisibility.full,
    profileVersion: 1,
    relationship: _relationship,
    allowedActions: ['editProfile', 'editPrivacy'],
  );
  PrivacySettings privacy = PrivacySettings(
    strangersCanViewProfile: true,
    searchableByFangyuanNumber: true,
    globalGroupMuted: false,
    updatedAt: DateTime(2026, 7, 30),
  );

  @override
  Future<UserProfile> loadMine() async => profile;

  @override
  Future<UserProfile> loadUser(String userId) async => profile;

  @override
  Future<PrivacySettings> loadPrivacy() async => privacy;

  @override
  Future<UserProfile> updateMine({
    required String ownerUserId,
    required int expectedVersion,
    String? nickname,
    ProfileGender? gender,
    String? signature,
    ProfileMediaChange avatar = const ProfileMediaChange.keep(),
    ProfileMediaChange background = const ProfileMediaChange.keep(),
  }) async {
    profile = UserProfile(
      userId: profile.userId,
      displayName: nickname ?? profile.displayName,
      fangyuanNumber: profile.fangyuanNumber,
      nickname: nickname ?? profile.nickname,
      gender: gender ?? profile.gender,
      signature: signature ?? profile.signature,
      visibility: profile.visibility,
      profileVersion: expectedVersion + 1,
      relationship: profile.relationship,
      allowedActions: profile.allowedActions,
      avatar: avatar.isSpecified ? null : profile.avatar,
      background: background.isSpecified ? null : profile.background,
    );
    return profile;
  }

  @override
  Future<PrivacySettings> updatePrivacy({
    bool? strangersCanViewProfile,
    bool? searchableByFangyuanNumber,
    bool? globalGroupMuted,
  }) async {
    privacy = PrivacySettings(
      strangersCanViewProfile:
          strangersCanViewProfile ?? privacy.strangersCanViewProfile,
      searchableByFangyuanNumber:
          searchableByFangyuanNumber ?? privacy.searchableByFangyuanNumber,
      globalGroupMuted: globalGroupMuted ?? privacy.globalGroupMuted,
      updatedAt: DateTime(2026, 7, 30, 1),
    );
    return privacy;
  }
}

void main() {
  testWidgets('从我的进入资料、编辑保存并按原路径返回', (tester) async {
    final repository = _ProfileRepository();
    repository.profile = UserProfile(
      userId: repository.profile.userId,
      displayName: repository.profile.displayName,
      fangyuanNumber: repository.profile.fangyuanNumber,
      nickname: repository.profile.nickname,
      gender: repository.profile.gender,
      signature: repository.profile.signature,
      visibility: repository.profile.visibility,
      profileVersion: repository.profile.profileVersion,
      relationship: repository.profile.relationship,
      allowedActions: repository.profile.allowedActions,
      avatar: const MediaAsset(mediaId: 'avatar-1', status: 'ready'),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: Scaffold(body: MyScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('小桃子'), findsOneWidget);
    final homeAvatar = tester.widget<ProfileAvatarImage>(
      find.byKey(const ValueKey('my-profile-avatar')),
    );
    expect(homeAvatar.media?.mediaId, 'avatar-1');
    await tester.tap(find.text('小桃子'));
    await tester.pumpAndSettle();
    expect(find.text('个人资料'), findsOneWidget);
    expect(find.text('今天也要开心'), findsOneWidget);

    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    expect(find.text('编辑资料'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '桃子同学');
    await tester.tap(find.text('女'));
    await tester.enterText(find.byType(TextField).last, '附近见，打个招呼');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('个人资料'), findsOneWidget);
    expect(find.text('桃子同学'), findsWidgets);
    expect(find.text('女'), findsOneWidget);
    expect(find.text('附近见，打个招呼'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('桃子同学'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('feature-entry-account_security')),
      250,
    );
    expect(find.text('账号与安全'), findsOneWidget);
  });

  testWidgets('开发中入口有统一反馈且不会进入空白页面', (tester) async {
    final repository = _ProfileRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: Scaffold(body: MyScreen())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('feature-entry-friend_posts')));
    await tester.pump();
    expect(find.text('好友动态功能开发中'), findsOneWidget);
    expect(find.byType(MyScreen), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('my-profile-qr')));
    await tester.pump();
    expect(find.text('我的二维码功能开发中'), findsOneWidget);
    expect(find.byType(MyScreen), findsOneWidget);
  });

  testWidgets('消息通知与免打扰在当前页切换真实状态', (tester) async {
    final repository = _ProfileRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: Scaffold(body: MyScreen())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('feature-entry-notifications')),
      250,
    );
    expect(find.text('未开启'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('feature-entry-notifications')));
    await tester.pumpAndSettle();

    expect(repository.privacy.globalGroupMuted, isTrue);
    expect(find.text('已开启'), findsOneWidget);
    expect(find.text('群消息免打扰已开启'), findsOneWidget);
  });

  testWidgets('账号与安全里的隐私开关保存真实状态', (tester) async {
    final repository = _ProfileRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: Scaffold(body: MyScreen())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('feature-entry-account_security')),
      250,
    );
    await tester.tap(
      find.byKey(const ValueKey('feature-entry-account_security')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('隐私'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile).first).value,
      isTrue,
    );
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(repository.privacy.strangersCanViewProfile, isFalse);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile).first).value,
      isFalse,
    );
  });
}
