import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/domain/auth_session.dart';
import '../network/authenticated_api_client.dart';
import 'realtime_cursor_store.dart';
import 'realtime_event.dart';
import 'realtime_socket.dart';
import 'realtime_sync_repository.dart';

enum RealtimeStatus { connecting, connected, retrying, stopped }

class RealtimeState {
  const RealtimeState({
    this.status = RealtimeStatus.connecting,
    this.navigationUnreadCount = 0,
    this.errorMessage,
  });

  final RealtimeStatus status;
  final int navigationUnreadCount;
  final String? errorMessage;

  RealtimeState copyWith({
    RealtimeStatus? status,
    int? navigationUnreadCount,
    String? errorMessage,
    bool clearError = false,
  }) {
    return RealtimeState(
      status: status ?? this.status,
      navigationUnreadCount:
          navigationUnreadCount ?? this.navigationUnreadCount,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

typedef RealtimeSessionLoader =
    Future<AuthSession?> Function({bool forceRefresh});
typedef ReconnectDelay = Future<void> Function(Duration duration);

class RealtimeController extends StateNotifier<RealtimeState> {
  RealtimeController(
    this._url,
    this._loadSession,
    this._connector,
    this._cursorStore,
    this._syncRepository, {
    ReconnectDelay? reconnectDelay,
    Uuid? uuid,
    Random? random,
  }) : _reconnectDelay =
           reconnectDelay ?? ((duration) => Future<void>.delayed(duration)),
       _uuid = uuid ?? const Uuid(),
       _random = random ?? Random(),
       super(const RealtimeState()) {
    unawaited(start());
  }

  final Uri _url;
  final RealtimeSessionLoader _loadSession;
  final RealtimeSocketConnector _connector;
  final RealtimeCursorStore _cursorStore;
  final RealtimeSyncRepository _syncRepository;
  final ReconnectDelay _reconnectDelay;
  final Uuid _uuid;
  final Random _random;
  final StreamController<RealtimeEvent> _events =
      StreamController<RealtimeEvent>.broadcast(sync: true);

  RealtimeSocket? _socket;
  bool _running = false;
  Future<void>? _runFuture;

  Stream<RealtimeEvent> get events => _events.stream;

  Future<void> start() {
    if (_running) return _runFuture ?? Future<void>.value();
    _running = true;
    return _runFuture = _run();
  }

  Future<void> ensureConnected() async {
    if (_running) return;
    await start();
  }

  Future<void> stop() async {
    _running = false;
    final socket = _socket;
    _socket = null;
    await socket?.close();
    if (mounted) {
      state = state.copyWith(status: RealtimeStatus.stopped);
    }
  }

  Future<void> _run() async {
    var attempt = 0;
    var forceRefresh = false;
    while (_running) {
      try {
        state = state.copyWith(
          status: attempt == 0
              ? RealtimeStatus.connecting
              : RealtimeStatus.retrying,
          clearError: true,
        );
        final session = await _loadSession(forceRefresh: forceRefresh);
        forceRefresh = false;
        if (!_running) return;
        if (session == null) {
          state = state.copyWith(
            status: RealtimeStatus.stopped,
            errorMessage: '登录状态已失效，请重新登录',
          );
          _running = false;
          return;
        }

        final socket = _connector.connect(
          _url,
          accessToken: session.accessToken,
        );
        _socket = socket;
        await socket.ready;
        if (!_running) {
          await socket.close();
          return;
        }

        final cursor = await _cursorStore.read(session.userId);
        socket.send(
          jsonEncode({
            'event': 'session.resume',
            'requestId': _uuid.v4(),
            'payload': {'resumeCursor': cursor},
          }),
        );
        attempt = 0;

        await _consume(socket, session.userId);
        forceRefresh = socket.closeCode == 4401;
      } catch (error) {
        if (!_running) return;
        state = state.copyWith(
          status: RealtimeStatus.retrying,
          errorMessage: '实时连接暂时中断，正在自动恢复',
        );
      } finally {
        _socket = null;
      }

      if (!_running) return;
      attempt += 1;
      final seconds = min(15, 1 << min(attempt - 1, 4));
      final jitter = _random.nextInt(400);
      await _reconnectDelay(Duration(seconds: seconds, milliseconds: jitter));
    }
  }

  Future<void> _consume(RealtimeSocket socket, String userId) async {
    await for (final raw in socket.stream) {
      await _handleRaw(raw, socket, userId);
    }
  }

  Future<void> _handleRaw(
    dynamic raw,
    RealtimeSocket socket,
    String userId,
  ) async {
    final decoded = jsonDecode(raw as String);
    if (decoded is! Map) return;
    final event = RealtimeEvent.fromJson(Map<String, dynamic>.from(decoded));

    if (event.name == 'heartbeat.ping') {
      final pingId = event.payload['pingId'];
      if (pingId is String) {
        socket.send(
          jsonEncode({
            'event': 'heartbeat.pong',
            'requestId': _uuid.v4(),
            'payload': {'pingId': pingId},
          }),
        );
      }
      return;
    }

    if (event.name == 'session.resync_required') {
      await _resync(userId);
      if (mounted) {
        state = state.copyWith(
          status: RealtimeStatus.connected,
          clearError: true,
        );
      }
      return;
    }

    await _recordAndEmit(userId, event);
  }

  Future<void> _resync(String userId) async {
    var cursor = await _cursorStore.read(userId) ?? '0-0';
    while (_running) {
      final page = await _syncRepository.load(afterCursor: cursor);
      for (final event in page.events) {
        await _recordAndEmit(userId, event);
      }
      cursor = page.latestCursor;
      await _cursorStore.write(userId, cursor);
      if (!page.hasMore) return;
    }
  }

  Future<void> _recordAndEmit(String userId, RealtimeEvent event) async {
    if (event.name == 'session.ready' && mounted) {
      state = state.copyWith(
        status: RealtimeStatus.connected,
        clearError: true,
      );
    }
    final cursor = event.cursor;
    if (cursor != null &&
        event.name != 'session.ready' &&
        event.name != 'realtime.error') {
      await _cursorStore.write(userId, cursor);
    }
    if (event.name == 'conversation.unread.changed') {
      final count = event.payload['navigationUnreadCount'];
      if (count is int && mounted) {
        state = state.copyWith(navigationUnreadCount: count);
      }
    }
    if (!_events.isClosed) _events.add(event);
  }

  @override
  void dispose() {
    unawaited(stop());
    unawaited(_events.close());
    super.dispose();
  }
}

final realtimeCursorStoreProvider = Provider<RealtimeCursorStore>(
  (_) => SecureRealtimeCursorStore(),
);

final realtimeSocketConnectorProvider = Provider<RealtimeSocketConnector>(
  (_) => const IoRealtimeSocketConnector(),
);

final realtimeSyncRepositoryProvider = Provider<RealtimeSyncRepository>((ref) {
  final environment = ref.watch(appEnvironmentProvider);
  final authController = ref.read(authControllerProvider.notifier);
  return HttpRealtimeSyncRepository(
    AuthenticatedApiClient(
      environment: environment,
      loadSession: authController.validSession,
    ),
  );
});

final realtimeControllerProvider =
    StateNotifierProvider.autoDispose<RealtimeController, RealtimeState>((ref) {
      final environment = ref.watch(appEnvironmentProvider);
      final authController = ref.read(authControllerProvider.notifier);
      return RealtimeController(
        Uri.parse(environment.realtimeUrl),
        authController.validSession,
        ref.watch(realtimeSocketConnectorProvider),
        ref.watch(realtimeCursorStoreProvider),
        ref.watch(realtimeSyncRepositoryProvider),
      );
    });
