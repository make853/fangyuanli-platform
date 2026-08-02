import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/realtime/realtime_controller.dart';
import '../../../core/realtime/realtime_event.dart';
import '../../auth/application/auth_controller.dart';
import '../data/friends_snapshot_store.dart';
import '../data/relationship_repository.dart';
import '../domain/friend_models.dart';

class FriendsState {
  const FriendsState({
    this.requests = const [],
    this.contacts = const [],
    this.blockedUsers = const [],
    this.processingRequestIds = const {},
    this.processingUserIds = const {},
    this.isLoading = false,
    this.errorMessage,
  });

  final List<FriendRequest> requests;
  final List<FriendContact> contacts;
  final List<BlockedUser> blockedUsers;
  final Set<String> processingRequestIds;
  final Set<String> processingUserIds;
  final bool isLoading;
  final String? errorMessage;

  int get pendingRequestCount => requests
      .where((request) => request.status == FriendRequestStatus.pending)
      .length;

  FriendsState copyWith({
    List<FriendRequest>? requests,
    List<FriendContact>? contacts,
    List<BlockedUser>? blockedUsers,
    Set<String>? processingRequestIds,
    Set<String>? processingUserIds,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
  }) {
    return FriendsState(
      requests: requests ?? this.requests,
      contacts: contacts ?? this.contacts,
      blockedUsers: blockedUsers ?? this.blockedUsers,
      processingRequestIds: processingRequestIds ?? this.processingRequestIds,
      processingUserIds: processingUserIds ?? this.processingUserIds,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

class FriendsController extends StateNotifier<FriendsState> {
  FriendsController(
    this._repository, {
    Stream<RealtimeEvent>? realtimeEvents,
    this.snapshotStore,
    this.ownerUserId,
  }) : super(const FriendsState()) {
    _subscription = realtimeEvents?.listen(_onRealtimeEvent);
    unawaited(_initialize());
  }

  final RelationshipRepository _repository;
  final FriendsSnapshotStore? snapshotStore;
  final String? ownerUserId;
  StreamSubscription<RealtimeEvent>? _subscription;
  Timer? _profileReloadTimer;
  Future<void>? _activeLoad;
  Future<void> _snapshotWrite = Future.value();

  FriendContact? contactForUser(String userId) {
    for (final contact in state.contacts) {
      if (contact.userId == userId) return contact;
    }
    return null;
  }

  Future<void> _initialize() async {
    final cached = await _readSnapshot();
    if (!mounted) return;
    if (cached != null) {
      state = state.copyWith(
        requests: cached.requests,
        contacts: cached.contacts,
        blockedUsers: cached.blockedUsers,
      );
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
    if (!silent) {
      state = state.copyWith(isLoading: true, clearError: true);
    }
    try {
      final results = await Future.wait([
        _repository.loadReceivedRequests(),
        _repository.loadFriends(),
        _repository.loadBlocks(),
      ]);
      final requestPage = results[0] as PageResult<FriendRequest>;
      final friendPage = results[1] as PageResult<FriendContact>;
      final blockPage = results[2] as PageResult<BlockedUser>;
      if (!mounted) return;
      state = state.copyWith(
        requests: requestPage.items,
        contacts: friendPage.items,
        blockedUsers: blockPage.items,
        isLoading: false,
        clearError: true,
      );
      _persistSnapshot();
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(isLoading: false, errorMessage: error.toString());
    }
  }

  Future<void> refreshContacts() async {
    try {
      final page = await _repository.loadFriends();
      if (!mounted) return;
      state = state.copyWith(contacts: page.items, clearError: true);
      _persistSnapshot();
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(errorMessage: error.toString());
    }
  }

  Future<bool> decide({required String requestId, required bool accept}) async {
    if (state.processingRequestIds.contains(requestId)) return false;
    state = state.copyWith(
      processingRequestIds: {...state.processingRequestIds, requestId},
      clearError: true,
    );

    try {
      final result = await _repository.decide(
        requestId: requestId,
        accept: accept,
      );
      var contacts = state.contacts;
      if (accept) {
        contacts = (await _repository.loadFriends()).items;
      }
      state = state.copyWith(
        requests: [
          for (final request in state.requests)
            if (request.requestId == requestId) result.request else request,
        ],
        contacts: contacts,
        processingRequestIds: {...state.processingRequestIds}
          ..remove(requestId),
      );
      _persistSnapshot();
      return true;
    } catch (error) {
      state = state.copyWith(
        processingRequestIds: {...state.processingRequestIds}
          ..remove(requestId),
        errorMessage: error.toString(),
      );
      return false;
    }
  }

  Future<bool> updateRemark(String friendUserId, String value) async {
    final trimmed = value.trim();
    return _updateSettings(
      friendUserId,
      () => _repository.updateFriendSettings(
        friendUserId: friendUserId,
        remarkName: trimmed.isEmpty ? null : trimmed,
        clearRemark: trimmed.isEmpty,
      ),
    );
  }

  Future<bool> updatePostPermission(String friendUserId, bool canViewMyPosts) {
    return _updateSettings(
      friendUserId,
      () => _repository.updateFriendSettings(
        friendUserId: friendUserId,
        canViewMyPosts: canViewMyPosts,
      ),
    );
  }

  Future<bool> updatePinned(String friendUserId, bool pinned) {
    return _updateSettings(
      friendUserId,
      () => _repository.updateFriendSettings(
        friendUserId: friendUserId,
        pinned: pinned,
      ),
    );
  }

  Future<bool> deleteFriend(String friendUserId) {
    return _performUserAction(friendUserId, () async {
      await _repository.deleteFriend(friendUserId);
      state = state.copyWith(
        contacts: [
          for (final contact in state.contacts)
            if (contact.userId != friendUserId) contact,
        ],
      );
    });
  }

  Future<bool> blockUser(String targetUserId) {
    return _performUserAction(targetUserId, () async {
      final blocked = await _repository.blockUser(targetUserId);
      state = state.copyWith(
        contacts: [
          for (final contact in state.contacts)
            if (contact.userId != targetUserId) contact,
        ],
        blockedUsers: [
          blocked,
          for (final item in state.blockedUsers)
            if (item.target.userId != targetUserId) item,
        ],
      );
    });
  }

  Future<bool> unblockUser(String targetUserId) {
    return _performUserAction(targetUserId, () async {
      final result = await _repository.unblockUser(targetUserId);
      var contacts = state.contacts;
      if (result.restoredRelation == PriorRelation.friend) {
        contacts = (await _repository.loadFriends()).items;
      }
      state = state.copyWith(
        contacts: contacts,
        blockedUsers: [
          for (final item in state.blockedUsers)
            if (item.target.userId != targetUserId) item,
        ],
      );
    });
  }

  Future<bool> _updateSettings(
    String friendUserId,
    Future<FriendSettings> Function() action,
  ) {
    return _performUserAction(friendUserId, () async {
      final settings = await action();
      final contacts = [
        for (final contact in state.contacts)
          if (contact.userId == friendUserId)
            contact.copyWith(
              remarkName: settings.remarkName,
              clearRemark: settings.remarkName == null,
              canViewMyPosts: settings.canViewMyPosts,
              pinned: settings.pinned,
            )
          else
            contact,
      ]..sort(_compareContacts);
      state = state.copyWith(contacts: contacts);
    });
  }

  Future<bool> _performUserAction(
    String userId,
    Future<void> Function() action,
  ) async {
    if (state.processingUserIds.contains(userId)) return false;
    state = state.copyWith(
      processingUserIds: {...state.processingUserIds, userId},
      clearError: true,
    );
    try {
      await action();
      state = state.copyWith(
        processingUserIds: {...state.processingUserIds}..remove(userId),
      );
      _persistSnapshot();
      return true;
    } catch (error) {
      state = state.copyWith(
        processingUserIds: {...state.processingUserIds}..remove(userId),
        errorMessage: error.toString(),
      );
      return false;
    }
  }

  static int _compareContacts(FriendContact left, FriendContact right) {
    if (left.pinned != right.pinned) return left.pinned ? -1 : 1;
    return left.visibleName.compareTo(right.visibleName);
  }

  Future<FriendsSnapshot?> _readSnapshot() async {
    final store = snapshotStore;
    final owner = ownerUserId;
    if (store == null || owner == null || owner.isEmpty) return null;
    try {
      return await store.read(owner);
    } catch (_) {
      return null;
    }
  }

  void _persistSnapshot() {
    final store = snapshotStore;
    final owner = ownerUserId;
    if (store == null || owner == null || owner.isEmpty) return;
    final snapshot = FriendsSnapshot(
      requests: List.of(state.requests),
      contacts: List.of(state.contacts),
      blockedUsers: List.of(state.blockedUsers),
    );
    _snapshotWrite = _snapshotWrite
        .then((_) => store.write(owner, snapshot))
        .catchError((_) {});
  }

  void _onRealtimeEvent(RealtimeEvent event) {
    if (event.name != 'profile.updated') return;
    final userId = event.payload['userId'];
    if (userId is! String || contactForUser(userId) == null) return;
    _profileReloadTimer?.cancel();
    _profileReloadTimer = Timer(
      const Duration(milliseconds: 180),
      () => unawaited(refreshContacts()),
    );
  }

  @override
  void dispose() {
    _profileReloadTimer?.cancel();
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}

final friendsControllerProvider =
    StateNotifierProvider.autoDispose<FriendsController, FriendsState>((ref) {
      final realtime = ref.watch(realtimeControllerProvider.notifier);
      return FriendsController(
        ref.watch(relationshipRepositoryProvider),
        realtimeEvents: realtime.events,
        snapshotStore: ref.watch(friendsSnapshotStoreProvider),
        ownerUserId: ref.watch(
          authControllerProvider.select((state) => state.session?.userId),
        ),
      );
    });
