import 'dart:async';

import 'package:fangyuanli_mobile/src/features/profile/application/user_profile_controller.dart';
import 'package:fangyuanli_mobile/src/features/profile/data/profile_repository.dart';
import 'package:fangyuanli_mobile/src/features/profile/data/profile_snapshot_store.dart';
import 'package:fangyuanli_mobile/src/features/profile/domain/profile_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('silent refresh keeps the last profile visible', () async {
    final repository = _ProfileRepository();
    final controller = UserProfileController(repository, 'user-b');

    await repository.firstLoad.future;
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.profile?.profileVersion, 1);

    final refresh = controller.load(silent: true);
    expect(controller.state.profile?.profileVersion, 1);
    expect(controller.state.isLoading, isFalse);
    expect(controller.state.isRefreshing, isTrue);

    repository.completeRefresh();
    await refresh;
    expect(controller.state.profile?.profileVersion, 2);
    expect(controller.state.isRefreshing, isFalse);

    controller.dispose();
  });

  test(
    'persistent snapshot is rendered before network refresh completes',
    () async {
      final repository = _DelayedProfileRepository();
      final snapshots = _MemoryProfileSnapshotStore()
        ..profiles['owner-a/user-b'] = _profile(version: 3);
      final controller = UserProfileController(
        repository,
        'user-b',
        snapshotStore: snapshots,
        ownerUserId: 'owner-a',
      );

      await _waitFor(() => controller.state.profile?.profileVersion == 3);
      expect(controller.state.isLoading, isFalse);
      expect(controller.state.isRefreshing, isTrue);

      repository.complete(_profile(version: 4));
      await _waitFor(() => controller.state.profile?.profileVersion == 4);
      expect(controller.state.isRefreshing, isFalse);
      expect(snapshots.profiles['owner-a/user-b']?.profileVersion, 4);

      controller.dispose();
    },
  );
}

class _ProfileRepository implements ProfileRepository {
  final firstLoad = Completer<void>();
  final _refresh = Completer<UserProfile>();
  var _loadCount = 0;

  @override
  Future<UserProfile> loadUser(String userId) async {
    _loadCount += 1;
    if (_loadCount == 1) {
      firstLoad.complete();
      return _profile(version: 1);
    }
    return _refresh.future;
  }

  void completeRefresh() => _refresh.complete(_profile(version: 2));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DelayedProfileRepository implements ProfileRepository {
  final _result = Completer<UserProfile>();

  void complete(UserProfile profile) => _result.complete(profile);

  @override
  Future<UserProfile> loadUser(String userId) => _result.future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemoryProfileSnapshotStore implements ProfileSnapshotStore {
  final profiles = <String, UserProfile>{};

  @override
  Future<UserProfile?> read({
    required String ownerUserId,
    required String targetUserId,
  }) async => profiles['$ownerUserId/$targetUserId'];

  @override
  Future<void> write({
    required String ownerUserId,
    required UserProfile profile,
  }) async {
    profiles['$ownerUserId/${profile.userId}'] = profile;
  }

  @override
  Future<void> clearOwner(String ownerUserId) async {
    profiles.removeWhere((key, _) => key.startsWith('$ownerUserId/'));
  }
}

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 50; attempt += 1) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  fail('condition was not met');
}

UserProfile _profile({required int version}) {
  return UserProfile(
    userId: 'user-b',
    displayName: '小桃子',
    fangyuanNumber: 'FY000000000002',
    nickname: '小桃子',
    gender: ProfileGender.unspecified,
    signature: '附近见',
    visibility: ProfileVisibility.full,
    profileVersion: version,
    relationship: const ProfileRelationship(
      state: ProfileRelationshipState.friend,
      canStartDirectChat: true,
      isBlockedByMe: false,
      hasBlockedMe: false,
      canViewMyPosts: true,
    ),
    allowedActions: const ['startDirectChat'],
  );
}
