import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/realtime/realtime_controller.dart';
import '../../auth/application/auth_controller.dart';
import '../../conversations/application/conversation_sync_controller.dart';
import '../../conversations/data/conversation_message_store.dart';
import '../../conversations/data/conversation_outbox_store.dart';
import '../../conversations/data/conversation_repository.dart';
import 'plaza_controller.dart';

@immutable
class PlazaChatScope {
  const PlazaChatScope({required this.conversationId});

  final String conversationId;

  @override
  bool operator ==(Object other) =>
      other is PlazaChatScope && other.conversationId == conversationId;

  @override
  int get hashCode => conversationId.hashCode;
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
        outboxStore: ref.watch(conversationOutboxStoreProvider),
        ownerUserId: ref.watch(
          authControllerProvider.select((state) => state.session?.userId),
        ),
        emptyConversationMessage: '当前广场会话暂不可用',
        accessContext: ConversationAccessContext.plaza(
          locationContextToken: ref
              .read(plazaControllerProvider)
              .locationContextToken,
        ),
        sendAccessResolver: ({required forceRefresh}) async {
          var plazaState = ref.read(plazaControllerProvider);
          final expiresAt = plazaState.locationContextExpiresAt;
          final hasUsableContext =
              plazaState.hasFreshEligibility &&
              plazaState.locationContextToken?.isNotEmpty == true &&
              expiresAt != null &&
              expiresAt.isAfter(
                DateTime.now().toUtc().add(const Duration(seconds: 30)),
              );
          if (forceRefresh || !hasUsableContext) {
            await ref
                .read(plazaControllerProvider.notifier)
                .refresh(silent: plazaState.plazas.isNotEmpty);
            plazaState = ref.read(plazaControllerProvider);
          }
          return ConversationAccessContext.plaza(
            locationContextToken: plazaState.locationContextToken,
          );
        },
      );
      return controller;
    });
