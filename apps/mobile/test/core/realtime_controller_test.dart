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

  test(
    'reconnects after transport loss and resumes from latest cursor',
    () async {
      final first = _FakeRealtimeSocket();
      final second = _FakeRealtimeSocket();
      final connector = _QueueConnector([first, second]);
      final cursorStore = _MemoryCursorStore()..value = '20-0';
      final reconnects = <Duration>[];
      final controller = RealtimeController(
        Uri.parse('ws://example.test/ws/v1'),
        ({bool forceRefresh = false}) async => _session,
        connector,
        cursorStore,
        _EmptySyncRepository(),
        reconnectDelay: (duration) async => reconnects.add(duration),
      );

      await _waitFor(() => first.sent.isNotEmpty);
      first.add(
        _serverEvent(
          'message.created',
          cursor: '21-0',
          payload: {'conversationId': 'conversation-1'},
        ),
      );
      await _waitFor(() => cursorStore.value == '21-0');

      await first.closeFromServer(1006);
      await _waitFor(() => second.sent.isNotEmpty);

      final resume = jsonDecode(second.sent.first) as Map<String, dynamic>;
      expect(
        (resume['payload'] as Map<String, dynamic>)['resumeCursor'],
        '21-0',
      );
      expect(reconnects, isNotEmpty);

      await controller.stop();
      controller.dispose();
    },
  );

  test(
    'refreshes the access token after an unauthorized socket close',
    () async {
      final first = _FakeRealtimeSocket();
      final second = _FakeRealtimeSocket();
      final connector = _QueueConnector([first, second]);
      final forceRefreshValues = <bool>[];
      final controller = RealtimeController(
        Uri.parse('ws://example.test/ws/v1'),
        ({bool forceRefresh = false}) async {
          forceRefreshValues.add(forceRefresh);
          return _session;
        },
        connector,
        _MemoryCursorStore(),
        _EmptySyncRepository(),
        reconnectDelay: (_) async {},
      );

      await _waitFor(() => first.sent.isNotEmpty);
      await first.closeFromServer(4401);
      await _waitFor(() => second.sent.isNotEmpty);

      expect(forceRefreshValues, [false, true]);

      await controller.stop();
      controller.dispose();
    },
  );

  test('rebuilds the socket when the app resumes from background', () async {
    final first = _FakeRealtimeSocket();
    final second = _FakeRealtimeSocket();
    final connector = _QueueConnector([first, second]);
    final controller = RealtimeController(
      Uri.parse('ws://example.test/ws/v1'),
      ({bool forceRefresh = false}) async => _session,
      connector,
      _MemoryCursorStore(),
      _EmptySyncRepository(),
      reconnectDelay: (_) async {},
    );

    await _waitFor(() => first.sent.isNotEmpty);
    await controller.recoverAfterResume();
    await _waitFor(() => second.sent.isNotEmpty);

    expect(first.wasClosed, isTrue);
    expect(connector.connectCount, 2);

    await controller.stop();
    controller.dispose();
  });

  test(
    'uses paged REST compensation when the realtime cursor expired',
    () async {
      final socket = _FakeRealtimeSocket();
      final cursorStore = _MemoryCursorStore()..value = '30-0';
      final syncRepository = _PagedSyncRepository([
        RealtimeSyncPage(
          events: [
            _event(
              'message.created',
              cursor: '31-0',
              payload: {'conversationId': 'conversation-1'},
            ),
          ],
          latestCursor: '31-0',
          hasMore: true,
        ),
        RealtimeSyncPage(
          events: [
            _event(
              'conversation.unread.changed',
              cursor: '32-0',
              payload: {'navigationUnreadCount': 2},
            ),
          ],
          latestCursor: '32-0',
          hasMore: false,
        ),
      ]);
      final controller = RealtimeController(
        Uri.parse('ws://example.test/ws/v1'),
        ({bool forceRefresh = false}) async => _session,
        _FakeConnector(socket),
        cursorStore,
        syncRepository,
        reconnectDelay: (_) async {},
      );
      final received = <String>[];
      final subscription = controller.events.listen(
        (event) => received.add(event.name),
      );

      await _waitFor(() => socket.sent.isNotEmpty);
      socket.add(_serverEvent('session.resync_required', cursor: '30-0'));
      await _waitFor(() => cursorStore.value == '32-0');

      expect(syncRepository.requestedCursors, ['30-0', '31-0']);
      expect(received, ['message.created', 'conversation.unread.changed']);
      expect(controller.state.navigationUnreadCount, 2);
      expect(controller.state.status, RealtimeStatus.connected);

      await subscription.cancel();
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

RealtimeEvent _event(
  String name, {
  required String cursor,
  Map<String, dynamic> payload = const {},
}) {
  return RealtimeEvent(name: name, cursor: cursor, payload: payload);
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

class _QueueConnector implements RealtimeSocketConnector {
  _QueueConnector(this.sockets);

  final List<_FakeRealtimeSocket> sockets;
  int connectCount = 0;

  @override
  RealtimeSocket connect(Uri uri, {required String accessToken}) {
    final socket = sockets[connectCount];
    connectCount += 1;
    return socket;
  }
}

class _FakeRealtimeSocket implements RealtimeSocket {
  final StreamController<dynamic> _controller = StreamController<dynamic>();
  final List<String> sent = [];
  int? _closeCode;
  bool wasClosed = false;

  void add(String value) => _controller.add(value);

  Future<void> closeFromServer(int code) async {
    _closeCode = code;
    await _controller.close();
  }

  @override
  int? get closeCode => _closeCode;

  @override
  Future<void> get ready async {}

  @override
  Stream<dynamic> get stream => _controller.stream;

  @override
  void send(String value) => sent.add(value);

  @override
  Future<void> close() async {
    wasClosed = true;
    _closeCode ??= 1000;
    await _controller.close();
  }
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

class _PagedSyncRepository implements RealtimeSyncRepository {
  _PagedSyncRepository(this.pages);

  final List<RealtimeSyncPage> pages;
  final List<String> requestedCursors = [];

  @override
  Future<RealtimeSyncPage> load({
    required String afterCursor,
    int limit = 200,
  }) async {
    requestedCursors.add(afterCursor);
    return pages[requestedCursors.length - 1];
  }
}
