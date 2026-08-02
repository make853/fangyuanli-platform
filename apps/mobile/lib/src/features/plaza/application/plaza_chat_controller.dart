import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/realtime/realtime_controller.dart';
import '../../auth/application/auth_controller.dart';
import '../../conversations/application/conversation_sync_controller.dart';
import '../../conversations/data/conversation_message_store.dart';
import '../../conversations/data/conversation_repository.dart';

@immutable
class PlazaChatScope {
  const PlazaChatScope({
    required this.conversationId,
    required this.locationContextToken,
  });

  final String conversationId;
  final String? locationContextToken;

  @override
  bool operator ==(Object other) =>
      other is PlazaChatScope &&
      other.conversationId == conversationId &&
      other.locationContextToken == locationContextToken;

  @override
  int get hashCode => Object.hash(conversationId, locationContextToken);
}

final plazaChatControllerProvider = StateNotifierProvider.autoDispose
    .family<ConversationSyncController, ConversationChatState, PlazaChatScope>((
      ref,
      scope,
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
        scope.conversationId,
        realtime.events,
        messageStore: ref.watch(conversationMessageStoreProvider),
        ownerUserId: ref.watch(
          authControllerProvider.select((state) => state.session?.userId),
        ),
        emptyConversationMessage: '当前广场会话暂不可用',
        accessContext: ConversationAccessContext.plaza(
          locationContextToken: scope.locationContextToken,
        ),
      );
      return controller;
    });
