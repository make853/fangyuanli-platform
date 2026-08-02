import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/realtime/realtime_controller.dart';
import '../../../core/realtime/realtime_event.dart';
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
    Stream<RealtimeEvent> realtimeEvents,
  ) : super(const ConversationListState()) {
    _subscription = realtimeEvents.listen(_onRealtimeEvent);
    unawaited(load());
  }

  final ConversationRepository _repository;
  late final StreamSubscription<RealtimeEvent> _subscription;
  Timer? _reloadTimer;

  Future<void> load({bool silent = false}) async {
    if (!silent) {
      state = state.copyWith(isLoading: true, clearError: true);
    }
    try {
      final page = await _repository.loadConversations();
      state = state.copyWith(
        items: page.items,
        navigationUnread: page.navigationUnread,
        isLoading: false,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(isLoading: false, errorMessage: error.toString());
    }
  }

  void _onRealtimeEvent(RealtimeEvent event) {
    if (event.name == 'conversation.unread.changed') {
      final count = event.payload['navigationUnreadCount'];
      if (count is int) {
        state = state.copyWith(navigationUnread: count);
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
  }

  void removeConversation(String conversationId) {
    state = state.copyWith(
      items: [
        for (final item in state.items)
          if (item.conversationId != conversationId) item,
      ],
    );
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
      );
    });
