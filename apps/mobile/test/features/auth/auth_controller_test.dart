import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fangyuanli_mobile/src/core/config/app_environment.dart';
import 'package:fangyuanli_mobile/src/core/storage/session_store.dart';
import 'package:fangyuanli_mobile/src/features/auth/application/auth_controller.dart';
import 'package:fangyuanli_mobile/src/features/auth/data/auth_api.dart';
import 'package:fangyuanli_mobile/src/features/auth/data/auth_repository.dart';
import 'package:fangyuanli_mobile/src/features/auth/domain/auth_session.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemorySessionStore implements SessionStore {
  _MemorySessionStore(this.value);

  AuthSession? value;

  @override
  Future<void> clear() async => value = null;

  @override
  Future<AuthSession?> read() async => value;

  @override
  Future<void> write(AuthSession session) async => value = session;
}

class _SlowAuthRepository extends AuthRepository {
  _SlowAuthRepository({
    required super.api,
    required super.sessionStore,
    required this.session,
  });

  final AuthSession session;
  final validationCompleter = Completer<AuthSession?>();
  int validationCount = 0;

  @override
  Future<AuthSession?> restore() async => session;

  @override
  Future<AuthSession?> ensureValid(
    AuthSession session, {
    bool forceRefresh = false,
  }) {
    validationCount += 1;
    return validationCompleter.future;
  }
}

void main() {
  const environment = AppEnvironment(
    flavor: AppFlavor.local,
    apiBaseUrl: 'http://127.0.0.1:3000',
    realtimeUrl: 'ws://127.0.0.1:3000/ws/v1',
  );
  final session = AuthSession(
    accessToken: 'access',
    accessTokenExpiresAt: DateTime.utc(2026, 7, 29, 12),
    refreshToken: 'refresh',
    refreshTokenExpiresAt: DateTime.utc(2026, 8, 29),
    deviceId: 'device',
    userId: 'user',
    isNewUser: false,
  );

  test('多个并发鉴权请求只触发一次令牌校验', () async {
    final repository = _SlowAuthRepository(
      api: AuthApi(environment: environment, dio: Dio()),
      sessionStore: _MemorySessionStore(session),
      session: session,
    );
    final controller = AuthController(repository);
    await Future<void>.delayed(Duration.zero);

    final first = controller.validSession();
    final second = controller.validSession(forceRefresh: true);

    expect(repository.validationCount, 1);
    repository.validationCompleter.complete(session);

    expect(await first, same(session));
    expect(await second, same(session));
  });
}
