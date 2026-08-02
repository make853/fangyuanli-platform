import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fangyuanli_mobile/src/core/config/app_environment.dart';
import 'package:fangyuanli_mobile/src/core/network/api_failure.dart';
import 'package:fangyuanli_mobile/src/core/network/authenticated_api_client.dart';
import 'package:fangyuanli_mobile/src/features/auth/domain/auth_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses an explicit idempotency key for restart-safe writes', () async {
    final adapter = _RecordingAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test'))
      ..httpClientAdapter = adapter;
    final client = AuthenticatedApiClient(
      environment: const AppEnvironment(
        flavor: AppFlavor.staging,
        apiBaseUrl: 'https://api.example.test',
        realtimeUrl: 'wss://api.example.test/ws/v1',
      ),
      loadSession: ({bool forceRefresh = false}) async => _session,
      dio: dio,
    );

    await client.post(
      '/media/uploads',
      data: const {'fileName': 'avatar.jpg'},
      idempotencyKey: 'stable-upload-key',
    );

    expect(adapter.options.headers['idempotency-key'], 'stable-upload-key');
    expect(adapter.options.headers['authorization'], 'Bearer access-token');
    expect(adapter.options.headers['x-device-id'], 'device-1');
  });

  test('blocks an account-affine request after the user changes', () async {
    final adapter = _RecordingAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test'))
      ..httpClientAdapter = adapter;
    final client = AuthenticatedApiClient(
      environment: const AppEnvironment(
        flavor: AppFlavor.staging,
        apiBaseUrl: 'https://api.example.test',
        realtimeUrl: 'wss://api.example.test/ws/v1',
      ),
      loadSession: ({bool forceRefresh = false}) async => _session,
      dio: dio,
    );

    await expectLater(
      client.post('/media/uploads/upload-1/complete', expectedUserId: 'user-2'),
      throwsA(
        isA<ApiFailure>().having(
          (failure) => failure.code,
          'code',
          'AUTH_ACCOUNT_CHANGED',
        ),
      ),
    );
    expect(adapter.calls, 0);
  });

  test('merges a plaza location context with authenticated headers', () async {
    final adapter = _RecordingAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test'))
      ..httpClientAdapter = adapter;
    final client = AuthenticatedApiClient(
      environment: const AppEnvironment(
        flavor: AppFlavor.staging,
        apiBaseUrl: 'https://api.example.test',
        realtimeUrl: 'wss://api.example.test/ws/v1',
      ),
      loadSession: ({bool forceRefresh = false}) async => _session,
      dio: dio,
    );

    await client.get(
      '/conversations/plaza-1/messages',
      headers: const {'x-location-context': 'opaque-plaza-context'},
    );

    expect(
      adapter.options.headers['x-location-context'],
      'opaque-plaza-context',
    );
    expect(adapter.options.headers['authorization'], 'Bearer access-token');
  });
}

final _session = AuthSession(
  accessToken: 'access-token',
  accessTokenExpiresAt: DateTime.utc(2026, 8, 1, 11),
  refreshToken: 'refresh-token',
  refreshTokenExpiresAt: DateTime.utc(2026, 8, 2, 10),
  deviceId: 'device-1',
  userId: 'user-1',
  isNewUser: false,
);

class _RecordingAdapter implements HttpClientAdapter {
  late RequestOptions options;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls += 1;
    this.options = options;
    return ResponseBody.fromString(
      '{"data":{"ok":true}}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
