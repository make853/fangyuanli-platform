import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/realtime/realtime_controller.dart';
import '../../../core/realtime/realtime_event.dart';
import '../../auth/application/auth_controller.dart';
import '../data/conversation_list_snapshot_store.dart';
import '../data/conversation_repository.dart';
import '../domain/conversation_summary.dart';

class ConversationListState {
  const ConversationListState({
    this.items = const [],
    this.navigationUnread = 0,
    this.isLoading = false,
    this.errorMessage,
  });

  final List<ConversationSummary> items;
  final int navigationUnread;
  final bool isLoading;
  final String? errorMessage;

  ConversationListState copyWith({
    List<ConversationSummary>? items,
    int? navigationUnread,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ConversationListState(
      items: items ?? this.items,
      navigationUnread: navigationUnread ?? this.navigationUnread,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

class ConversationListController extends StateNotifier<ConversationListState> {
  ConversationListController(
    this._repository,
    Stream<RealtimeEvent> realtimeEvents, {
    this.snapshotStore,
    this.ownerUserId,
  }) : super(const ConversationListState()) {
    _subscription = realtimeEvents.listen(_onRealtimeEvent);
    unawaited(_initialize());
  }

  final ConversationRepository _repository;
  final ConversationListSnapshotStore? snapshotStore;
  final String? ownerUserId;
  late final StreamSubscription<RealtimeEvent> _subscription;
  Timer? _reloadTimer;
  Future<void>? _activeLoad;
  Future<void> _snapshotWrite = Future.value();

  Future<void> _initialize() async {
    final cached = await _readSnapshot();
    if (!mounted) return;
    if (cached != null) {
      state = state.copyWith(
        items: cached.items,
        navigationUnread: cached.navigationUnread,
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
      final page = await _repository.loadConversations();
      if (!mounted) return;
      state = state.copyWith(
        items: page.items,
        navigationUnread: page.navigationUnread,
        isLoading: false,
        clearError: true,
      );
      _persistSnapshot();
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(isLoading: false, errorMessage: error.toString());
    }
  }

  void _onRealtimeEvent(RealtimeEvent event) {
    if (event.name == 'conversation.unread.changed') {
      final navigationKey = event.payload['navigationKey'];
      if (navigationKey != null && navigationKey != 'friends') return;
      final count = event.payload['navigationUnreadCount'];
      if (count is int) {
        state = state.copyWith(navigationUnread: count);
        _persistSnapshot();
      }
      _scheduleReload();
      return;
    }
    if (event.name == 'message.created' ||
        event.name == 'conversation.snapshot' ||
        event.name == 'profile.updated') {
      _scheduleReload();
    }
  }

  void _scheduleReload() {
    _reloadTimer?.cancel();
    _reloadTimer = Timer(
      const Duration(milliseconds: 120),
      () => unawaited(load(silent: true)),
    );
  }

  void applyFriendProjection({
    required String conversationId,
    required String title,
    required bool pinned,
  }) {
    final items = [
      for (final item in state.items)
        if (item.conversationId == conversationId)
          item.copyWith(title: title, pinned: pinned)
        else
          item,
    ];
    _sortConversations(items);
    state = state.copyWith(items: items);
    _persistSnapshot();
  }

  void removeConversation(String conversationId) {
    state = state.copyWith(
      items: [
        for (final item in state.items)
          if (item.conversationId != conversationId) item,
      ],
    );
    _persistSnapshot();
  }

  Future<ConversationListSnapshot?> _readSnapshot() async {
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
    final snapshot = ConversationListSnapshot(
      items: List.of(state.items),
      navigationUnread: state.navigationUnread,
    );
    _snapshotWrite = _snapshotWrite
        .then((_) => store.write(owner, snapshot))
        .catchError((_) {});
  }

  static void _sortConversations(List<ConversationSummary> items) {
    items.sort((left, right) {
      if (left.pinned != right.pinned) return left.pinned ? -1 : 1;
      final leftTime = left.lastMessage?.createdAt;
      final rightTime = right.lastMessage?.createdAt;
      if (leftTime == null && rightTime == null) return 0;
      if (leftTime == null) return 1;
      if (rightTime == null) return -1;
      return rightTime.compareTo(leftTime);
    });
  }

  @override
  void dispose() {
    _reloadTimer?.cancel();
    unawaited(_subscription.cancel());
    super.dispose();
  }
}

final conversationListControllerProvider =
    StateNotifierProvider.autoDispose<
      ConversationListController,
      ConversationListState
    >((ref) {
      final realtime = ref.watch(realtimeControllerProvider.notifier);
      return ConversationListController(
        ref.watch(conversationRepositoryProvider),
        realtime.events,
        snapshotStore: ref.watch(conversationListSnapshotStoreProvider),
        ownerUserId: ref.watch(
          authControllerProvider.select((state) => state.session?.userId),
        ),
      );
    });
