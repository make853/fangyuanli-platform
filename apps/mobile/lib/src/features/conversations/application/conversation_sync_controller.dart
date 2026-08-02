import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/realtime/realtime_event.dart';
import '../data/conversation_message_store.dart';
import '../data/conversation_repository.dart';
import '../domain/conversation_message.dart';

class ConversationChatState {
  const ConversationChatState({
    this.messages = const [],
    this.isLoading = false,
    this.isRefreshing = false,
    this.isSending = false,
    this.hasEarlier = false,
    this.errorMessage,
  });

  final List<ConversationMessage> messages;
  final bool isLoading;
  final bool isRefreshing;
  final bool isSending;
  final bool hasEarlier;
  final String? errorMessage;

  ConversationChatState copyWith({
    List<ConversationMessage>? messages,
    bool? isLoading,
    bool? isRefreshing,
    bool? isSending,
    bool? hasEarlier,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ConversationChatState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      isSending: isSending ?? this.isSending,
      hasEarlier: hasEarlier ?? this.hasEarlier,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

/// Shared local-first sync engine for every conversation scene.
///
/// Scene-specific access checks remain on the server/repository boundary; this
/// controller owns only cache hydration, sequence sync, realtime merge and read
/// cursor progression.
class ConversationSyncController extends StateNotifier<ConversationChatState> {
  ConversationSyncController(
    this._repository,
    this._conversationId,
    Stream<RealtimeEvent> realtimeEvents, {
    this.messageStore,
    this.ownerUserId,
    this.emptyConversationMessage = '当前会话暂不可用',
    this.accessContext = const ConversationAccessContext.direct(),
  }) : super(const ConversationChatState()) {
    _subscription = realtimeEvents.listen(_onRealtimeEvent);
    unawaited(_initialize());
  }

  final ConversationRepository _repository;
  final String _conversationId;
  final ConversationMessageStore? messageStore;
  final String? ownerUserId;
  final String emptyConversationMessage;
  final ConversationAccessContext accessContext;
  late final StreamSubscription<RealtimeEvent> _subscription;
  Future<void>? _activeLoad;

  bool get hasCachedMessages => state.messages.isNotEmpty;

  Future<void> _initialize() async {
    final cached = await _readCachedMessages();
    if (!mounted) return;
    if (cached != null) {
      state = state.copyWith(
        messages: cached.messages,
        hasEarlier: cached.hasEarlier,
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
    if (_conversationId.isEmpty) {
      state = state.copyWith(errorMessage: emptyConversationMessage);
      return;
    }
    final keepVisible = silent && state.messages.isNotEmpty;
    state = state.copyWith(
      isLoading: !keepVisible,
      isRefreshing: keepVisible,
      clearError: true,
    );
    try {
      final existing = state.messages;
      final latestSequence = existing.isEmpty ? null : existing.last.sequence;
      var page = await _repository.loadMessages(
        _conversationId,
        afterSequence: latestSequence,
        limit: latestSequence == null ? 50 : 100,
        access: accessContext,
      );
      var messages = latestSequence == null
          ? page.items
          : _mergeMessages(existing, page.items);
      var hasEarlier = latestSequence == null
          ? page.hasEarlier
          : state.hasEarlier || page.hasEarlier;
      var pageCount = 1;
      while (page.hasLater && page.items.isNotEmpty && pageCount < 50) {
        page = await _repository.loadMessages(
          _conversationId,
          afterSequence: page.items.last.sequence,
          limit: 100,
          access: accessContext,
        );
        messages = _mergeMessages(messages, page.items);
        hasEarlier = hasEarlier || page.hasEarlier;
        pageCount += 1;
      }
      if (!mounted) return;
      state = state.copyWith(
        messages: messages,
        hasEarlier: hasEarlier,
        isLoading: false,
        isRefreshing: false,
      );
      await _writeCachedMessages(messages, hasEarlier: hasEarlier);
      if (messages.isNotEmpty) {
        unawaited(_markRead(messages.last.sequence));
      }
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        isRefreshing: false,
        errorMessage: error.toString(),
      );
    }
  }

  Future<bool> send(String value) async {
    final text = value.trim();
    if (text.isEmpty || state.isSending) return false;
    state = state.copyWith(isSending: true, clearError: true);
    try {
      final message = await _repository.sendText(
        _conversationId,
        text,
        access: accessContext,
      );
      state = state.copyWith(
        messages: _mergeMessage(state.messages, message),
        isSending: false,
      );
      unawaited(_writeCachedMessages([message], hasEarlier: state.hasEarlier));
      unawaited(_markRead(message.sequence));
      return true;
    } catch (error) {
      state = state.copyWith(isSending: false, errorMessage: error.toString());
      return false;
    }
  }

  Future<void> _markRead(int sequence) async {
    try {
      await _repository.markRead(
        _conversationId,
        sequence,
        access: accessContext,
      );
    } catch (_) {
      // Read receipts must not interrupt loading or sending messages.
    }
  }

  void _onRealtimeEvent(RealtimeEvent event) {
    if (event.name != 'message.created') return;
    if (event.payload['conversationId'] != _conversationId) return;
    try {
      final message = ConversationMessage.fromJson(event.payload);
      state = state.copyWith(
        messages: _mergeMessage(state.messages, message),
        clearError: true,
      );
      unawaited(_writeCachedMessages([message], hasEarlier: state.hasEarlier));
      unawaited(_markRead(message.sequence));
    } catch (_) {
      unawaited(load(silent: state.messages.isNotEmpty));
    }
  }

  Future<ConversationMessageSnapshot?> _readCachedMessages() async {
    final store = messageStore;
    final owner = ownerUserId;
    if (store == null || owner == null || owner.isEmpty) return null;
    try {
      return await store.readRecent(
        ownerUserId: owner,
        conversationId: _conversationId,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCachedMessages(
    Iterable<ConversationMessage> messages, {
    required bool hasEarlier,
  }) async {
    final store = messageStore;
    final owner = ownerUserId;
    if (store == null || owner == null || owner.isEmpty) return;
    try {
      await store.write(
        ownerUserId: owner,
        conversationId: _conversationId,
        messages: messages,
        hasEarlier: hasEarlier,
      );
    } catch (_) {
      // Server messages stay usable when the local cache is unavailable.
    }
  }

  List<ConversationMessage> _mergeMessage(
    List<ConversationMessage> messages,
    ConversationMessage message,
  ) {
    final merged = [
      for (final item in messages)
        if (item.messageId != message.messageId &&
            item.sequence != message.sequence)
          item,
      message,
    ]..sort((left, right) => left.sequence.compareTo(right.sequence));
    return merged;
  }

  List<ConversationMessage> _mergeMessages(
    List<ConversationMessage> current,
    Iterable<ConversationMessage> incoming,
  ) {
    var merged = current;
    for (final message in incoming) {
      merged = _mergeMessage(merged, message);
    }
    return merged;
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
