import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/realtime/realtime_controller.dart';
import '../../auth/application/auth_controller.dart';
import '../data/conversation_message_store.dart';
import '../data/conversation_outbox_store.dart';
import '../data/conversation_repository.dart';
import 'conversation_sync_controller.dart';

typedef DirectChatState = ConversationChatState;
typedef DirectChatController = ConversationSyncController;

/// Direct chat is currently the first scene adapter using the shared engine.
/// Plaza, place and activity providers will supply their own access context but
/// must reuse [ConversationSyncController].
final directChatControllerProvider = StateNotifierProvider.autoDispose
    .family<ConversationSyncController, ConversationChatState, String>((
      ref,
      conversationId,
    ) {
      final keepAlive = ref.keepAlive();
      Timer? idleTimer;
      late final ConversationSyncController controller;
      final realtime = ref.watch(realtimeControllerProvider.notifier);
      ref.onCancel(() {
        idleTimer = Timer(const Duration(minutes: 10), keepAlive.close);
      });
      ref.onResume(() {
        idleTimer?.cancel();
        if (controller.hasCachedMessages) {
          unawaited(controller.load(silent: true));
        }
      });
      ref.onDispose(() => idleTimer?.cancel());

      controller = ConversationSyncController(
        ref.watch(conversationRepositoryProvider),
        conversationId,
        realtime.events,
        messageStore: ref.watch(conversationMessageStoreProvider),
        outboxStore: ref.watch(conversationOutboxStoreProvider),
        ownerUserId: ref.watch(
          authControllerProvider.select((state) => state.session?.userId),
        ),
        emptyConversationMessage: '当前好友尚未建立私聊会话',
      );
      return controller;
    });
