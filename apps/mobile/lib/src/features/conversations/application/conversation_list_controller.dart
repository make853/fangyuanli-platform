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
        event.name == 'conversation.snapshot') {
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
