import '../network/authenticated_api_client.dart';
import 'realtime_event.dart';

class RealtimeSyncPage {
  const RealtimeSyncPage({
    required this.events,
    required this.latestCursor,
    required this.hasMore,
  });

  final List<RealtimeEvent> events;
  final String latestCursor;
  final bool hasMore;
}

abstract interface class RealtimeSyncRepository {
  Future<RealtimeSyncPage> load({required String afterCursor, int limit = 200});
}

class HttpRealtimeSyncRepository implements RealtimeSyncRepository {
  HttpRealtimeSyncRepository(this._client);

  final AuthenticatedApiClient _client;

  @override
  Future<RealtimeSyncPage> load({
    required String afterCursor,
    int limit = 200,
  }) async {
    final envelope = await _client.get(
      '/sync/events',
      queryParameters: {'afterCursor': afterCursor, 'limit': limit},
    );
    final rawData = envelope['data'];
    if (rawData is! Map) {
      throw const FormatException('服务器返回的同步数据格式不正确');
    }
    final data = Map<String, dynamic>.from(rawData);
    final rawEvents = data['events'];
    if (rawEvents is! List) {
      throw const FormatException('服务器返回的同步事件格式不正确');
    }
    return RealtimeSyncPage(
      events: [
        for (final rawEvent in rawEvents)
          _eventFromSync(Map<String, dynamic>.from(rawEvent as Map)),
      ],
      latestCursor: data['latestCursor'] as String,
      hasMore: data['hasMore'] as bool? ?? false,
    );
  }

  RealtimeEvent _eventFromSync(Map<String, dynamic> json) {
    return RealtimeEvent.fromJson({
      'event': json['eventType'],
      'eventId': json['eventId'],
      'eventCursor': json['eventCursor'],
      'serverTime': json['occurredAt'],
      'payload': json['payload'],
    });
  }
}
