import 'dart:async';
import 'dart:convert';

import 'package:fangyuanli_mobile/src/core/realtime/realtime_controller.dart';
import 'package:fangyuanli_mobile/src/core/realtime/realtime_cursor_store.dart';
import 'package:fangyuanli_mobile/src/core/realtime/realtime_event.dart';
import 'package:fangyuanli_mobile/src/core/realtime/realtime_socket.dart';
import 'package:fangyuanli_mobile/src/core/realtime/realtime_sync_repository.dart';
import 'package:fangyuanli_mobile/src/features/auth/domain/auth_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'resumes with saved cursor, handles heartbeat, and persists events',
    () async {
      final socket = _FakeRealtimeSocket();
      final connector = _FakeConnector(socket);
      final cursorStore = _MemoryCursorStore()..value = '12-0';
      final controller = RealtimeController(
        Uri.parse('ws://example.test/ws/v1'),
        ({bool forceRefresh = false}) async => _session,
        connector,
        cursorStore,
        _EmptySyncRepository(),
        reconnectDelay: (_) async {},
      );

      await connector.connected.future;
      await _waitFor(() => socket.sent.isNotEmpty);

      final resume = jsonDecode(socket.sent.first) as Map<String, dynamic>;
      expect(resume['event'], 'session.resume');
      expect(
        (resume['payload'] as Map<String, dynamic>)['resumeCursor'],
        '12-0',
      );

      socket.add(_serverEvent('session.ready', cursor: '12-0'));
      await _waitFor(() => controller.state.status == RealtimeStatus.connected);

      socket.add(
        _serverEvent(
          'heartbeat.ping',
          cursor: '12-0',
          payload: {'pingId': 'ping-1'},
        ),
      );
      await _waitFor(() => socket.sent.length == 2);
      expect(
        (jsonDecode(socket.sent.last) as Map<String, dynamic>)['event'],
        'heartbeat.pong',
      );

      final received = controller.events.firstWhere(
        (event) => event.name == 'message.created',
      );
      socket.add(
        _serverEvent(
          'message.created',
          cursor: '13-0',
          payload: {'conversationId': 'conversation-1'},
        ),
      );
      expect((await received).cursor, '13-0');
      expect(cursorStore.value, '13-0');

      await controller.stop();
      controller.dispose();
    },
  );
}

final _session = AuthSession(
  accessToken: 'access-token',
  accessTokenExpiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
  refreshToken: 'refresh-token',
  refreshTokenExpiresAt: DateTime.now().toUtc().add(const Duration(days: 1)),
  deviceId: 'device-1',
  userId: 'user-1',
  isNewUser: false,
);

String _serverEvent(
  String name, {
  required String cursor,
  Map<String, dynamic> payload = const {},
}) {
  return jsonEncode({
    'event': name,
    'requestId': null,
    'eventId': 'event-$name',
    'eventCursor': cursor,
    'serverTime': '2026-07-30T00:00:00.000Z',
    'payload': payload,
  });
}

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 30; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('condition was not reached');
}

class _FakeConnector implements RealtimeSocketConnector {
  _FakeConnector(this.socket);

  final _FakeRealtimeSocket socket;
  final Completer<void> connected = Completer<void>();

  @override
  RealtimeSocket connect(Uri uri, {required String accessToken}) {
    if (!connected.isCompleted) connected.complete();
    return socket;
  }
}

class _FakeRealtimeSocket implements RealtimeSocket {
  final StreamController<dynamic> _controller = StreamController<dynamic>();
  final List<String> sent = [];

  void add(String value) => _controller.add(value);

  @override
  int? get closeCode => 1000;

  @override
  Future<void> get ready async {}

  @override
  Stream<dynamic> get stream => _controller.stream;

  @override
  void send(String value) => sent.add(value);

  @override
  Future<void> close() => _controller.close();
}

class _MemoryCursorStore implements RealtimeCursorStore {
  String? value;

  @override
  Future<void> clear(String userId) async => value = null;

  @override
  Future<String?> read(String userId) async => value;

  @override
  Future<void> write(String userId, String cursor) async => value = cursor;
}

class _EmptySyncRepository implements RealtimeSyncRepository {
  @override
  Future<RealtimeSyncPage> load({
    required String afterCursor,
    int limit = 200,
  }) async {
    return RealtimeSyncPage(
      events: const <RealtimeEvent>[],
      latestCursor: afterCursor,
      hasMore: false,
    );
  }
}
