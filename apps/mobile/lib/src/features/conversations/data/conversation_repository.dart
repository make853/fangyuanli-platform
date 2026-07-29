import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/api_failure.dart';
import '../../../core/network/authenticated_api_client.dart';
import '../../auth/application/auth_controller.dart';
import '../domain/conversation_summary.dart';
import '../domain/direct_message.dart';

abstract interface class ConversationRepository {
  Future<ConversationListPage> loadConversations();

  Future<DirectMessagePage> loadMessages(String conversationId);

  Future<DirectMessage> sendText(String conversationId, String text);

  Future<void> markRead(String conversationId, int lastReadSequence);
}

class HttpConversationRepository implements ConversationRepository {
  HttpConversationRepository(this._client, {Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  final AuthenticatedApiClient _client;
  final Uuid _uuid;

  @override
  Future<ConversationListPage> loadConversations() async {
    final envelope = await _client.get(
      '/conversations',
      queryParameters: const {'limit': 50},
    );
    final data = _data(envelope);
    final rawItems = data['items'];
    if (rawItems is! List) {
      throw const ApiFailure(message: '服务器返回的会话格式不正确');
    }
    return ConversationListPage(
      items: [
        for (final item in rawItems)
          ConversationSummary.fromJson(Map<String, dynamic>.from(item as Map)),
      ],
      navigationUnread: data['navigationUnread'] as int? ?? 0,
      hasMore: data['hasMore'] as bool? ?? false,
    );
  }

  @override
  Future<DirectMessagePage> loadMessages(String conversationId) async {
    final envelope = await _client.get(
      '/conversations/$conversationId/messages',
      queryParameters: const {'limit': 50},
    );
    final data = _data(envelope);
    final rawItems = data['items'];
    if (rawItems is! List) {
      throw const ApiFailure(message: '服务器返回的消息格式不正确');
    }
    return DirectMessagePage(
      items: [
        for (final item in rawItems)
          DirectMessage.fromJson(Map<String, dynamic>.from(item as Map)),
      ],
      hasEarlier: data['hasEarlier'] as bool? ?? false,
      hasLater: data['hasLater'] as bool? ?? false,
    );
  }

  @override
  Future<DirectMessage> sendText(String conversationId, String text) async {
    final envelope = await _client.post(
      '/conversations/$conversationId/messages',
      idempotent: true,
      data: {'clientMessageId': _uuid.v4(), 'type': 'text', 'text': text},
    );
    return DirectMessage.fromJson(_data(envelope));
  }

  @override
  Future<void> markRead(String conversationId, int lastReadSequence) async {
    await _client.put(
      '/conversations/$conversationId/read-cursor',
      idempotent: true,
      data: {'lastReadSequence': lastReadSequence},
    );
  }

  Map<String, dynamic> _data(Map<String, dynamic> envelope) {
    final data = envelope['data'];
    if (data is! Map<String, dynamic>) {
      throw const ApiFailure(message: '服务器返回的数据格式不正确');
    }
    return data;
  }
}

final conversationRepositoryProvider = Provider<ConversationRepository>((ref) {
  final environment = ref.watch(appEnvironmentProvider);
  final authController = ref.read(authControllerProvider.notifier);
  return HttpConversationRepository(
    AuthenticatedApiClient(
      environment: environment,
      loadSession: authController.validSession,
    ),
  );
});
