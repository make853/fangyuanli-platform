import 'package:dio/dio.dart';
import 'package:fangyuanli_mobile/src/core/config/app_environment.dart';
import 'package:fangyuanli_mobile/src/core/storage/session_store.dart';
import 'package:fangyuanli_mobile/src/features/auth/data/auth_api.dart';
import 'package:fangyuanli_mobile/src/features/auth/data/auth_repository.dart';
import 'package:fangyuanli_mobile/src/features/auth/domain/auth_session.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemorySessionStore implements SessionStore {
  AuthSession? value;

  @override
  Future<void> clear() async => value = null;

  @override
  Future<AuthSession?> read() async => value;

  @override
  Future<void> write(AuthSession session) async => value = session;
}

void main() {
  final environment = AppEnvironment(
    flavor: AppFlavor.local,
    apiBaseUrl: 'http://127.0.0.1:3000',
    realtimeUrl: 'ws://127.0.0.1:3000/ws/v1',
  );

  test('过期的刷新令牌会清除本地登录状态', () async {
    final store = _MemorySessionStore()
      ..value = AuthSession(
        accessToken: 'access',
        accessTokenExpiresAt: DateTime.utc(2026, 7, 1),
        refreshToken: 'refresh',
        refreshTokenExpiresAt: DateTime.utc(2026, 7, 2),
        deviceId: 'device',
        userId: 'user',
        isNewUser: false,
      );
    final repository = AuthRepository(
      api: AuthApi(environment: environment, dio: Dio()),
      sessionStore: store,
      clock: () => DateTime.utc(2026, 7, 29),
    );

    final restored = await repository.restore();

    expect(restored, isNull);
    expect(store.value, isNull);
  });

  test('有效访问令牌无需刷新即可继续使用', () async {
    final session = AuthSession(
      accessToken: 'access',
      accessTokenExpiresAt: DateTime.utc(2026, 7, 29, 12),
      refreshToken: 'refresh',
      refreshTokenExpiresAt: DateTime.utc(2026, 8, 29),
      deviceId: 'device',
      userId: 'user',
      isNewUser: false,
    );
    final store = _MemorySessionStore()..value = session;
    final repository = AuthRepository(
      api: AuthApi(environment: environment, dio: Dio()),
      sessionStore: store,
      clock: () => DateTime.utc(2026, 7, 29, 10),
    );

    final restored = await repository.ensureValid(session);

    expect(restored, same(session));
    expect(store.value, same(session));
  });
}
