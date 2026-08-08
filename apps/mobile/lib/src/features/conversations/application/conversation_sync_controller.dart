import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/api_failure.dart';
import '../../../core/realtime/realtime_event.dart';
import '../../media/domain/media_upload_models.dart';
import '../data/conversation_message_store.dart';
import '../data/conversation_outbox_store.dart';
import '../data/conversation_repository.dart';
import '../domain/conversation_message.dart';

class ConversationChatState {
  const ConversationChatState({
    this.messages = const [],
    this.isLoading = false,
    this.isRefreshing = false,
    this.isLoadingEarlier = false,
    this.isLoadingLater = false,
    this.hasEarlier = false,
    this.hasLater = false,
    this.isAnchored = false,
    this.errorMessage,
  });

  final List<ConversationMessage> messages;
  final bool isLoading;
  final bool isRefreshing;
  final bool isLoadingEarlier;
  final bool isLoadingLater;
  final bool hasEarlier;
  final bool hasLater;
  final bool isAnchored;
  final String? errorMessage;

  ConversationChatState copyWith({
    List<ConversationMessage>? messages,
    bool? isLoading,
    bool? isRefreshing,
    bool? isLoadingEarlier,
    bool? isLoadingLater,
    bool? hasEarlier,
    bool? hasLater,
    bool? isAnchored,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ConversationChatState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      isLoadingEarlier: isLoadingEarlier ?? this.isLoadingEarlier,
      isLoadingLater: isLoadingLater ?? this.isLoadingLater,
      hasEarlier: hasEarlier ?? this.hasEarlier,
      hasLater: hasLater ?? this.hasLater,
      isAnchored: isAnchored ?? this.isAnchored,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

typedef ConversationSendAccessResolver =
    Future<ConversationAccessContext> Function({required bool forceRefresh});

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
    this.outboxStore,
    this.ownerUserId,
    this.emptyConversationMessage = '当前会话暂不可用',
    this.accessContext = const ConversationAccessContext.direct(),
    this.sendAccessResolver,
    Uuid? uuid,
  }) : _uuid = uuid ?? const Uuid(),
       super(
         _initialState(
           messageStore: messageStore,
           outboxStore: outboxStore,
           ownerUserId: ownerUserId,
           conversationId: _conversationId,
         ),
       ) {
    _subscription = realtimeEvents.listen(_onRealtimeEvent);
    _latestMessages = state.messages;
    unawaited(_initialize());
  }

  final ConversationRepository _repository;
  final String _conversationId;
  final ConversationMessageStore? messageStore;
  final ConversationOutboxStore? outboxStore;
  final String? ownerUserId;
  final String emptyConversationMessage;
  final ConversationAccessContext accessContext;
  final ConversationSendAccessResolver? sendAccessResolver;
  late final StreamSubscription<RealtimeEvent> _subscription;
  Future<void>? _activeLoad;
  Future<bool>? _activeEarlierLoad;
  Future<bool>? _activeLaterLoad;
  Future<bool>? _activeAnchorLoad;
  final Uuid _uuid;
  bool _isReadVisible = false;
  int? _lastReadSequenceRequested;
  List<ConversationMessage> _latestMessages = const [];

  bool get hasCachedMessages => state.messages.isNotEmpty;

  /// Controls whether synchronized messages are actually visible to the user.
  ///
  /// Providers intentionally keep a conversation alive for a short time after
  /// its screen closes. Realtime synchronization may continue in that window,
  /// but it must not advance the read cursor until a visible chat surface owns
  /// the conversation again.
  void setReadVisible(bool visible) {
    if (_isReadVisible == visible) return;
    _isReadVisible = visible;
    if (!visible) return;
    final latestSequence = _latestConfirmedSequence(state.messages);
    if (latestSequence != null) {
      unawaited(_markRead(latestSequence));
    }
  }

  Future<void> _initialize() async {
    final cachedResults = await Future.wait<Object?>([
      _readCachedMessages(),
      _readOutboxMessages(),
    ]);
    final cached = cachedResults[0] as ConversationMessageSnapshot?;
    final outbox = cachedResults[1] as List<ConversationMessage>;
    if (!mounted) return;
    if (cached != null || outbox.isNotEmpty) {
      final messages = _mergeMessages(cached?.messages ?? const [], outbox);
      _latestMessages = messages;
      state = state.copyWith(
        messages: messages,
        hasEarlier: cached?.hasEarlier ?? state.hasEarlier,
      );
    }
    await load(silent: state.messages.isNotEmpty);
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
      final anchored = state.isAnchored;
      final existing = anchored ? _latestMessages : state.messages;
      final latestSequence = _latestConfirmedSequence(existing);
      var page = await _repository.loadMessages(
        _conversationId,
        afterSequence: latestSequence,
        limit: latestSequence == null ? 50 : 100,
        access: accessContext,
      );
      var messages = latestSequence == null
          ? _mergeMessages(
              page.items,
              existing.where((message) => message.isPending),
            )
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
      _latestMessages = messages;
      state = anchored
          ? state.copyWith(isLoading: false, isRefreshing: false)
          : state.copyWith(
              messages: messages,
              hasEarlier: hasEarlier,
              hasLater: page.hasLater,
              isLoading: false,
              isRefreshing: false,
            );
      await _writeCachedMessages(messages, hasEarlier: hasEarlier);
      final confirmedSequence = _latestConfirmedSequence(messages);
      if (confirmedSequence != null) {
        unawaited(_markRead(confirmedSequence));
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

  /// Prepends the next contiguous page without replacing the visible window.
  ///
  /// The presentation layer preserves the current visual offset while this
  /// method only owns sequence paging, merging and persistence.
  Future<bool> loadEarlier() {
    final active = _activeEarlierLoad;
    if (active != null) return active;
    if (!state.hasEarlier || state.isLoadingEarlier) {
      return Future.value(false);
    }
    final request = _loadEarlier();
    _activeEarlierLoad = request;
    return request.whenComplete(() {
      if (identical(_activeEarlierLoad, request)) _activeEarlierLoad = null;
    });
  }

  Future<bool> _loadEarlier() async {
    final earliestSequence = _earliestConfirmedSequence(state.messages);
    if (earliestSequence == null) return false;
    state = state.copyWith(isLoadingEarlier: true, clearError: true);
    try {
      final page = await _repository.loadMessages(
        _conversationId,
        beforeSequence: earliestSequence,
        limit: 50,
        access: accessContext,
      );
      if (!mounted) return false;
      final messages = _mergeMessages(state.messages, page.items);
      final changed = messages.length != state.messages.length;
      state = state.copyWith(
        messages: messages,
        hasEarlier: page.hasEarlier,
        isLoadingEarlier: false,
      );
      if (!state.isAnchored) _latestMessages = messages;
      await _writeCachedMessages(page.items, hasEarlier: page.hasEarlier);
      return changed;
    } catch (error) {
      if (!mounted) return false;
      state = state.copyWith(
        isLoadingEarlier: false,
        errorMessage: error.toString(),
      );
      return false;
    }
  }

  /// Appends the next contiguous page after an anchor/search window.
  Future<bool> loadLater() {
    final active = _activeLaterLoad;
    if (active != null) return active;
    if (!state.hasLater || state.isLoadingLater) return Future.value(false);
    final request = _loadLater();
    _activeLaterLoad = request;
    return request.whenComplete(() {
      if (identical(_activeLaterLoad, request)) _activeLaterLoad = null;
    });
  }

  Future<bool> _loadLater() async {
    final latestSequence = _latestConfirmedSequence(state.messages);
    if (latestSequence == null) return false;
    state = state.copyWith(isLoadingLater: true, clearError: true);
    try {
      final page = await _repository.loadMessages(
        _conversationId,
        afterSequence: latestSequence,
        limit: 50,
        access: accessContext,
      );
      if (!mounted) return false;
      var messages = _mergeMessages(state.messages, page.items);
      if (!page.hasLater) {
        messages = _mergeMessages(messages, _latestMessages);
      }
      final changed = messages.length != state.messages.length;
      state = state.copyWith(
        messages: messages,
        hasLater: page.hasLater,
        isAnchored: page.hasLater,
        isLoadingLater: false,
      );
      if (!page.hasLater) _latestMessages = messages;
      await _writeCachedMessages(page.items, hasEarlier: state.hasEarlier);
      return changed;
    } catch (error) {
      if (!mounted) return false;
      state = state.copyWith(
        isLoadingLater: false,
        errorMessage: error.toString(),
      );
      return false;
    }
  }

  /// Loads a contiguous context window around a search or unread sequence.
  /// Existing pending messages stay durable in the outbox, while confirmed
  /// messages are replaced by the anchored window to avoid silently rendering
  /// a non-contiguous timeline as if no messages were missing.
  Future<bool> loadAround(int sequence) {
    if (sequence <= 0) return Future.value(false);
    if (state.messages.any(
      (message) => !message.isPending && message.sequence == sequence,
    )) {
      return Future.value(true);
    }
    final active = _activeAnchorLoad;
    if (active != null) return active;
    final request = _loadAround(sequence);
    _activeAnchorLoad = request;
    return request.whenComplete(() {
      if (identical(_activeAnchorLoad, request)) _activeAnchorLoad = null;
    });
  }

  Future<bool> _loadAround(int sequence) async {
    state = state.copyWith(
      isLoadingEarlier: true,
      isLoadingLater: true,
      clearError: true,
    );
    try {
      final page = await _repository.loadMessages(
        _conversationId,
        anchorSequence: sequence,
        limit: 50,
        access: accessContext,
      );
      if (!mounted) return false;
      if (!state.isAnchored) _latestMessages = state.messages;
      final messages = _mergeMessages(const [], page.items);
      final found = messages.any(
        (message) => !message.isPending && message.sequence == sequence,
      );
      state = state.copyWith(
        messages: messages,
        hasEarlier: page.hasEarlier,
        hasLater: page.hasLater,
        isAnchored: page.hasEarlier || page.hasLater,
        isLoadingEarlier: false,
        isLoadingLater: false,
      );
      await _writeCachedMessages(page.items, hasEarlier: page.hasEarlier);
      return found;
    } catch (error) {
      if (!mounted) return false;
      state = state.copyWith(
        isLoadingEarlier: false,
        isLoadingLater: false,
        errorMessage: error.toString(),
      );
      return false;
    }
  }

  Future<bool> send(
    String value, {
    String senderName = '我',
    int senderProfileVersion = 1,
    MediaAsset? senderAvatar,
  }) async {
    final text = value.trim();
    if (text.isEmpty || _conversationId.isEmpty) return false;
    final clientMessageId = _uuid.v4();
    final localMessage = ConversationMessage(
      messageId: 'local:$clientMessageId',
      clientMessageId: clientMessageId,
      conversationId: _conversationId,
      sequence: 0,
      senderUserId: ownerUserId,
      senderName: senderName,
      senderProfileVersion: senderProfileVersion,
      senderAvatar: senderAvatar,
      text: text,
      createdAt: DateTime.now(),
      deliveryState: 'sending',
    );
    final base = state.isAnchored ? _latestMessages : state.messages;
    final messages = _mergeMessage(base, localMessage);
    _latestMessages = messages;
    state = state.copyWith(
      messages: messages,
      hasLater: false,
      isAnchored: false,
      clearError: true,
    );
    unawaited(_writeOutboxMessage(localMessage));
    unawaited(_deliver(localMessage));
    return true;
  }

  bool retry(String clientMessageId) {
    ConversationMessage? failed;
    for (final message in state.messages) {
      if (message.clientMessageId == clientMessageId &&
          message.deliveryState == 'failed') {
        failed = message;
        break;
      }
    }
    if (failed == null) return false;
    final retrying = failed.copyWith(deliveryState: 'sending');
    final messages = _mergeMessage(_latestMessages, retrying);
    _latestMessages = messages;
    state = state.copyWith(messages: messages, clearError: true);
    unawaited(_writeOutboxMessage(retrying));
    unawaited(_deliver(retrying));
    return true;
  }

  Future<void> _deliver(ConversationMessage localMessage) async {
    final clientMessageId = localMessage.clientMessageId!;
    try {
      var deliveryAccess = await _resolveSendAccess(forceRefresh: false);
      ConversationMessage message;
      try {
        message = await _sendLocalMessage(localMessage, deliveryAccess);
      } on ApiFailure catch (error) {
        if (sendAccessResolver == null || !_canRefreshSendAccess(error.code)) {
          rethrow;
        }
        deliveryAccess = await _resolveSendAccess(forceRefresh: true);
        message = await _sendLocalMessage(localMessage, deliveryAccess);
      }
      if (!mounted) return;
      final messages = _mergeMessage(_latestMessages, message);
      _latestMessages = messages;
      state = state.copyWith(messages: messages);
      unawaited(_writeCachedMessages([message], hasEarlier: state.hasEarlier));
      unawaited(_deleteOutboxMessage(clientMessageId));
      unawaited(_markRead(message.sequence));
    } catch (_) {
      if (!mounted) return;
      final failed = localMessage.copyWith(deliveryState: 'failed');
      final messages = _mergeMessage(_latestMessages, failed);
      _latestMessages = messages;
      state = state.copyWith(messages: messages);
      unawaited(_writeOutboxMessage(failed));
    }
  }

  Future<ConversationAccessContext> _resolveSendAccess({
    required bool forceRefresh,
  }) async {
    final resolver = sendAccessResolver;
    if (resolver == null) return accessContext;
    return resolver(forceRefresh: forceRefresh);
  }

  Future<ConversationMessage> _sendLocalMessage(
    ConversationMessage localMessage,
    ConversationAccessContext deliveryAccess,
  ) {
    return _repository.sendText(
      _conversationId,
      localMessage.text ?? '',
      clientMessageId: localMessage.clientMessageId!,
      access: deliveryAccess,
    );
  }

  bool _canRefreshSendAccess(String? code) => switch (code) {
    'PLAZA_LOCATION_CONTEXT_REQUIRED' ||
    'PLAZA_LOCATION_NOT_AUTHORIZED' ||
    'LOCATION_CONTEXT_EXPIRED' ||
    'LOCATION_CONTEXT_INVALID' ||
    'LOCATION_CONTEXT_USER_INVALID' => true,
    _ => false,
  };

  Future<void> _markRead(int sequence) async {
    if (!_isReadVisible ||
        (_lastReadSequenceRequested != null &&
            sequence <= _lastReadSequenceRequested!)) {
      return;
    }
    _lastReadSequenceRequested = sequence;
    try {
      await _repository.markRead(
        _conversationId,
        sequence,
        access: accessContext,
      );
    } catch (_) {
      if (_lastReadSequenceRequested == sequence) {
        _lastReadSequenceRequested = null;
      }
      // Read receipts must not interrupt loading or sending messages.
    }
  }

  void _onRealtimeEvent(RealtimeEvent event) {
    if (event.name != 'message.created') return;
    if (event.payload['conversationId'] != _conversationId) return;
    try {
      final message = ConversationMessage.fromJson(event.payload);
      _latestMessages = _mergeMessage(_latestMessages, message);
      if (!state.isAnchored) {
        state = state.copyWith(messages: _latestMessages, clearError: true);
      }
      unawaited(_writeCachedMessages([message], hasEarlier: state.hasEarlier));
      final clientMessageId = message.clientMessageId;
      if (clientMessageId != null) {
        unawaited(_deleteOutboxMessage(clientMessageId));
      }
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

  Future<List<ConversationMessage>> _readOutboxMessages() async {
    final store = outboxStore;
    final owner = ownerUserId;
    if (store == null || owner == null || owner.isEmpty) return const [];
    try {
      final messages = await store.read(
        ownerUserId: owner,
        conversationId: _conversationId,
      );
      final restored = [
        for (final message in messages)
          message.deliveryState == 'sending'
              ? message.copyWith(deliveryState: 'failed')
              : message,
      ];
      for (final message in restored) {
        if (message.deliveryState != 'sending') {
          unawaited(_writeOutboxMessage(message));
        }
      }
      return restored;
    } catch (_) {
      return const [];
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
      final confirmed = messages.where((message) => !message.isPending);
      if (confirmed.isEmpty) return;
      await store.write(
        ownerUserId: owner,
        conversationId: _conversationId,
        messages: confirmed,
        hasEarlier: hasEarlier,
      );
    } catch (_) {
      // Server messages stay usable when the local cache is unavailable.
    }
  }

  Future<void> _writeOutboxMessage(ConversationMessage message) async {
    final store = outboxStore;
    final owner = ownerUserId;
    if (store == null || owner == null || owner.isEmpty) return;
    try {
      await store.upsert(ownerUserId: owner, message: message);
    } catch (_) {
      // Optimistic UI stays usable if durable local storage is unavailable.
    }
  }

  Future<void> _deleteOutboxMessage(String clientMessageId) async {
    final store = outboxStore;
    final owner = ownerUserId;
    if (store == null || owner == null || owner.isEmpty) return;
    try {
      await store.delete(
        ownerUserId: owner,
        conversationId: _conversationId,
        clientMessageId: clientMessageId,
      );
    } catch (_) {
      // A stale acknowledged row is deduplicated by clientMessageId next load.
    }
  }

  List<ConversationMessage> _mergeMessage(
    List<ConversationMessage> messages,
    ConversationMessage message,
  ) {
    final merged = [
      for (final item in messages)
        if (item.messageId != message.messageId &&
            (message.clientMessageId == null ||
                item.clientMessageId != message.clientMessageId) &&
            (message.isPending ||
                item.isPending ||
                item.sequence != message.sequence))
          item,
      message,
    ]..sort(_compareMessages);
    return merged;
  }

  int _compareMessages(ConversationMessage left, ConversationMessage right) {
    if (left.isPending != right.isPending) return left.isPending ? 1 : -1;
    if (left.isPending) return left.createdAt.compareTo(right.createdAt);
    return left.sequence.compareTo(right.sequence);
  }

  int? _latestConfirmedSequence(List<ConversationMessage> messages) {
    int? latest;
    for (final message in messages) {
      if (message.isPending) continue;
      if (latest == null || message.sequence > latest) {
        latest = message.sequence;
      }
    }
    return latest;
  }

  int? _earliestConfirmedSequence(List<ConversationMessage> messages) {
    int? earliest;
    for (final message in messages) {
      if (message.isPending) continue;
      if (earliest == null || message.sequence < earliest) {
        earliest = message.sequence;
      }
    }
    return earliest;
  }

  static ConversationChatState _initialState({
    required ConversationMessageStore? messageStore,
    required ConversationOutboxStore? outboxStore,
    required String? ownerUserId,
    required String conversationId,
  }) {
    if (ownerUserId == null || ownerUserId.isEmpty) {
      return const ConversationChatState();
    }
    final cached = messageStore?.peekRecent(
      ownerUserId: ownerUserId,
      conversationId: conversationId,
    );
    final outbox =
        outboxStore?.peek(
          ownerUserId: ownerUserId,
          conversationId: conversationId,
        ) ??
        const <ConversationMessage>[];
    final combined =
        [
          ...?cached?.messages,
          for (final message in outbox)
            message.deliveryState == 'sending'
                ? message.copyWith(deliveryState: 'failed')
                : message,
        ]..sort((left, right) {
          if (left.isPending != right.isPending) return left.isPending ? 1 : -1;
          if (left.isPending) return left.createdAt.compareTo(right.createdAt);
          return left.sequence.compareTo(right.sequence);
        });
    return ConversationChatState(
      messages: List.unmodifiable(combined),
      hasEarlier: cached?.hasEarlier ?? false,
    );
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
