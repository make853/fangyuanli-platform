import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../data/profile_repository.dart';
import '../data/profile_snapshot_store.dart';
import '../domain/profile_models.dart';

class UserProfileState {
  const UserProfileState({
    this.profile,
    this.isLoading = false,
    this.isRefreshing = false,
    this.errorMessage,
  });

  final UserProfile? profile;
  final bool isLoading;
  final bool isRefreshing;
  final String? errorMessage;

  UserProfileState copyWith({
    UserProfile? profile,
    bool? isLoading,
    bool? isRefreshing,
    String? errorMessage,
    bool clearError = false,
  }) {
    return UserProfileState(
      profile: profile ?? this.profile,
      isLoading: isLoading ?? this.isLoading,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

class UserProfileController extends StateNotifier<UserProfileState> {
  UserProfileController(
    this._repository,
    this._userId, {
    this.snapshotStore,
    this.ownerUserId,
  }) : super(const UserProfileState()) {
    unawaited(_initialize());
  }

  final ProfileRepository _repository;
  final String _userId;
  final ProfileSnapshotStore? snapshotStore;
  final String? ownerUserId;
  Future<void>? _activeLoad;

  bool get hasCachedProfile => state.profile != null;

  Future<void> _initialize() async {
    state = state.copyWith(isLoading: true, clearError: true);
    final cached = await _readCachedProfile();
    if (cached != null) {
      state = state.copyWith(profile: cached, isLoading: false);
    }
    await load(silent: cached != null);
  }

  Future<void> load({bool silent = false}) {
    final active = _activeLoad;
    if (active != null) return active;
    final request = _load(silent: silent);
    _activeLoad = request;
    return request.whenComplete(() {
      if (identical(_activeLoad, request)) _activeLoad = null;
    });
  }

  Future<void> _load({required bool silent}) async {
    final keepVisible = silent && state.profile != null;
    state = state.copyWith(
      isLoading: !keepVisible,
      isRefreshing: keepVisible,
      clearError: true,
    );
    try {
      final profile = await _repository.loadUser(_userId);
      state = state.copyWith(
        profile: profile,
        isLoading: false,
        isRefreshing: false,
        clearError: true,
      );
      await _writeCachedProfile(profile);
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        isRefreshing: false,
        errorMessage: error.toString(),
      );
    }
  }

  Future<UserProfile?> _readCachedProfile() async {
    final store = snapshotStore;
    final owner = ownerUserId;
    if (store == null || owner == null || owner.isEmpty) {
      return null;
    }
    try {
      return await store.read(ownerUserId: owner, targetUserId: _userId);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCachedProfile(UserProfile profile) async {
    final store = snapshotStore;
    final owner = ownerUserId;
    if (store == null || owner == null || owner.isEmpty) return;
    try {
      await store.write(ownerUserId: owner, profile: profile);
    } catch (_) {
      // Network data remains usable even when the local cache is unavailable.
    }
  }
}

final userProfileControllerProvider = StateNotifierProvider.autoDispose
    .family<UserProfileController, UserProfileState, String>((ref, userId) {
      final keepAlive = ref.keepAlive();
      Timer? idleTimer;
      late final UserProfileController controller;

      ref.onCancel(() {
        idleTimer = Timer(const Duration(minutes: 10), keepAlive.close);
      });
      ref.onResume(() {
        idleTimer?.cancel();
        if (controller.hasCachedProfile) {
          unawaited(controller.load(silent: true));
        }
      });
      ref.onDispose(() => idleTimer?.cancel());

      controller = UserProfileController(
        ref.watch(profileRepositoryProvider),
        userId,
        snapshotStore: ref.watch(profileSnapshotStoreProvider),
        ownerUserId: ref.watch(
          authControllerProvider.select((state) => state.session?.userId),
        ),
      );
      return controller;
    });
