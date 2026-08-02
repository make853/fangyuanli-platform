import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/api_failure.dart';
import '../../../core/network/authenticated_api_client.dart';
import '../../../core/network/authenticated_api_client_provider.dart';
import '../domain/conversation_summary.dart';
import '../domain/conversation_message.dart';

abstract interface class ConversationRepository {
  Future<ConversationListPage> loadConversations();

  Future<ConversationMessagePage> loadMessages(
    String conversationId, {
    int? beforeSequence,
    int? afterSequence,
    int? anchorSequence,
    int limit = 50,
    ConversationAccessContext access = const ConversationAccessContext.direct(),
  });

  Future<ConversationMessage> sendText(
    String conversationId,
    String text, {
    ConversationAccessContext access = const ConversationAccessContext.direct(),
  });

  Future<void> markRead(
    String conversationId,
    int lastReadSequence, {
    ConversationAccessContext access = const ConversationAccessContext.direct(),
  });
}

enum ConversationScene { direct, plaza, place, activity, system }

class ConversationAccessContext {
  const ConversationAccessContext.direct()
    : scene = ConversationScene.direct,
      locationContextToken = null;

  const ConversationAccessContext.plaza({required this.locationContextToken})
    : scene = ConversationScene.plaza;

  final ConversationScene scene;
  final String? locationContextToken;

  Map<String, dynamic>? get headers {
    final token = locationContextToken?.trim();
    if (token == null || token.isEmpty) return null;
    return {'x-location-context': token};
  }
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
  Future<ConversationMessagePage> loadMessages(
    String conversationId, {
    int? beforeSequence,
    int? afterSequence,
    int? anchorSequence,
    int limit = 50,
    ConversationAccessContext access = const ConversationAccessContext.direct(),
  }) async {
    final query = <String, dynamic>{'limit': limit};
    if (beforeSequence != null) query['beforeSequence'] = beforeSequence;
    if (afterSequence != null) query['afterSequence'] = afterSequence;
    if (anchorSequence != null) query['anchorSequence'] = anchorSequence;
    final envelope = await _client.get(
      '/conversations/$conversationId/messages',
      queryParameters: query,
      headers: access.headers,
    );
    final data = _data(envelope);
    final rawItems = data['items'];
    if (rawItems is! List) {
      throw const ApiFailure(message: '服务器返回的消息格式不正确');
    }
    return ConversationMessagePage(
      items: [
        for (final item in rawItems)
          ConversationMessage.fromJson(Map<String, dynamic>.from(item as Map)),
      ],
      hasEarlier: data['hasEarlier'] as bool? ?? false,
      hasLater: data['hasLater'] as bool? ?? false,
    );
  }

  @override
  Future<ConversationMessage> sendText(
    String conversationId,
    String text, {
    ConversationAccessContext access = const ConversationAccessContext.direct(),
  }) async {
    final envelope = await _client.post(
      '/conversations/$conversationId/messages',
      idempotent: true,
      headers: access.headers,
      data: {'clientMessageId': _uuid.v4(), 'type': 'text', 'text': text},
    );
    return ConversationMessage.fromJson(_data(envelope));
  }

  @override
  Future<void> markRead(
    String conversationId,
    int lastReadSequence, {
    ConversationAccessContext access = const ConversationAccessContext.direct(),
  }) async {
    await _client.put(
      '/conversations/$conversationId/read-cursor',
      idempotent: true,
      headers: access.headers,
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
  return HttpConversationRepository(ref.watch(authenticatedApiClientProvider));
});
