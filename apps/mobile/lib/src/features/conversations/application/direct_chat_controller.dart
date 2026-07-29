import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/conversation_repository.dart';
import '../domain/direct_message.dart';

class DirectChatState {
  const DirectChatState({
    this.messages = const [],
    this.isLoading = false,
    this.isSending = false,
    this.hasEarlier = false,
    this.errorMessage,
  });

  final List<DirectMessage> messages;
  final bool isLoading;
  final bool isSending;
  final bool hasEarlier;
  final String? errorMessage;

  DirectChatState copyWith({
    List<DirectMessage>? messages,
    bool? isLoading,
    bool? isSending,
    bool? hasEarlier,
    String? errorMessage,
    bool clearError = false,
  }) {
    return DirectChatState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      isSending: isSending ?? this.isSending,
      hasEarlier: hasEarlier ?? this.hasEarlier,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

class DirectChatController extends StateNotifier<DirectChatState> {
  DirectChatController(this._repository, this._conversationId)
    : super(const DirectChatState()) {
    unawaited(load());
  }

  final ConversationRepository _repository;
  final String _conversationId;

  Future<void> load() async {
    if (_conversationId.isEmpty) {
      state = state.copyWith(errorMessage: '当前好友尚未建立私聊会话');
      return;
    }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final page = await _repository.loadMessages(_conversationId);
      state = state.copyWith(
        messages: page.items,
        hasEarlier: page.hasEarlier,
        isLoading: false,
      );
      if (page.items.isNotEmpty) {
        unawaited(_markRead(page.items.last.sequence));
      }
    } catch (error) {
      state = state.copyWith(isLoading: false, errorMessage: error.toString());
    }
  }

  Future<bool> send(String value) async {
    final text = value.trim();
    if (text.isEmpty || state.isSending) return false;
    state = state.copyWith(isSending: true, clearError: true);
    try {
      final message = await _repository.sendText(_conversationId, text);
      state = state.copyWith(
        messages: _mergeMessage(state.messages, message),
        isSending: false,
      );
      unawaited(_markRead(message.sequence));
      return true;
    } catch (error) {
      state = state.copyWith(isSending: false, errorMessage: error.toString());
      return false;
    }
  }

  Future<void> _markRead(int sequence) async {
    try {
      await _repository.markRead(_conversationId, sequence);
    } catch (_) {
      // Read receipts must not interrupt loading or sending messages.
    }
  }

  List<DirectMessage> _mergeMessage(
    List<DirectMessage> messages,
    DirectMessage message,
  ) {
    final merged = [
      for (final item in messages)
        if (item.messageId != message.messageId) item,
      message,
    ]..sort((left, right) => left.sequence.compareTo(right.sequence));
    return merged;
  }
}

final directChatControllerProvider = StateNotifierProvider.autoDispose
    .family<DirectChatController, DirectChatState, String>(
      (ref, conversationId) => DirectChatController(
        ref.watch(conversationRepositoryProvider),
        conversationId,
      ),
    );
