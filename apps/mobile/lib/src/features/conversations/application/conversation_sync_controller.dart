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
    this.hasEarlier = false,
    this.errorMessage,
  });

  final List<ConversationMessage> messages;
  final bool isLoading;
  final bool isRefreshing;
  final bool hasEarlier;
  final String? errorMessage;

  ConversationChatState copyWith({
    List<ConversationMessage>? messages,
    bool? isLoading,
    bool? isRefreshing,
    bool? hasEarlier,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ConversationChatState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      hasEarlier: hasEarlier ?? this.hasEarlier,
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
  final Uuid _uuid;

  bool get hasCachedMessages => state.messages.isNotEmpty;

  Future<void> _initialize() async {
    final cachedResults = await Future.wait<Object?>([
      _readCachedMessages(),
      _readOutboxMessages(),
    ]);
    final cached = cachedResults[0] as ConversationMessageSnapshot?;
    final outbox = cachedResults[1] as List<ConversationMessage>;
    if (!mounted) return;
    if (cached != null || outbox.isNotEmpty) {
      state = state.copyWith(
        messages: _mergeMessages(cached?.messages ?? const [], outbox),
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
      final existing = state.messages;
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
      state = state.copyWith(
        messages: messages,
        hasEarlier: hasEarlier,
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
    state = state.copyWith(
      messages: _mergeMessage(state.messages, localMessage),
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
    state = state.copyWith(
      messages: _mergeMessage(state.messages, retrying),
      clearError: true,
    );
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
      state = state.copyWith(messages: _mergeMessage(state.messages, message));
      unawaited(_writeCachedMessages([message], hasEarlier: state.hasEarlier));
      unawaited(_deleteOutboxMessage(clientMessageId));
      unawaited(_markRead(message.sequence));
    } catch (_) {
      if (!mounted) return;
      final failed = localMessage.copyWith(deliveryState: 'failed');
      state = state.copyWith(messages: _mergeMessage(state.messages, failed));
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
