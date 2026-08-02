import 'package:dio/dio.dart';
import 'package:fangyuanli_mobile/src/core/config/app_environment.dart';
import 'package:fangyuanli_mobile/src/core/network/api_failure.dart';
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

class _RefreshAuthApi extends AuthApi {
  _RefreshAuthApi({required super.environment, required this.result});

  final Future<AuthSession> Function(AuthSession session) result;
  int refreshCount = 0;

  @override
  Future<AuthSession> refresh(AuthSession session) {
    refreshCount += 1;
    return result(session);
  }
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

  test('冷启动以有效刷新凭证立即恢复，不等待访问令牌续期', () async {
    final session = AuthSession(
      accessToken: 'expired-access',
      accessTokenExpiresAt: DateTime.utc(2026, 7, 29, 9),
      refreshToken: 'refresh',
      refreshTokenExpiresAt: DateTime.utc(2026, 8, 29),
      deviceId: 'device',
      userId: 'user',
      isNewUser: false,
    );
    final store = _MemorySessionStore()..value = session;
    final api = _RefreshAuthApi(
      environment: environment,
      result: (_) => throw const ApiFailure(message: '不应在冷启动刷新'),
    );
    final repository = AuthRepository(
      api: api,
      sessionStore: store,
      clock: () => DateTime.utc(2026, 7, 29, 10),
    );

    final restored = await repository.restore();

    expect(restored, same(session));
    expect(api.refreshCount, 0);
    expect(store.value, same(session));
  });

  test('访问令牌续期遇到断网时保留本地登录', () async {
    final session = AuthSession(
      accessToken: 'expired-access',
      accessTokenExpiresAt: DateTime.utc(2026, 7, 29, 9),
      refreshToken: 'refresh',
      refreshTokenExpiresAt: DateTime.utc(2026, 8, 29),
      deviceId: 'device',
      userId: 'user',
      isNewUser: false,
    );
    final store = _MemorySessionStore()..value = session;
    final repository = AuthRepository(
      api: _RefreshAuthApi(
        environment: environment,
        result: (_) => throw const ApiFailure(message: '暂时无法连接服务器'),
      ),
      sessionStore: store,
      clock: () => DateTime.utc(2026, 7, 29, 10),
    );

    final restored = await repository.ensureValid(session);

    expect(restored, same(session));
    expect(store.value, same(session));
  });

  test('访问令牌续期被服务器拒绝时清除登录', () async {
    final session = AuthSession(
      accessToken: 'expired-access',
      accessTokenExpiresAt: DateTime.utc(2026, 7, 29, 9),
      refreshToken: 'invalid-refresh',
      refreshTokenExpiresAt: DateTime.utc(2026, 8, 29),
      deviceId: 'device',
      userId: 'user',
      isNewUser: false,
    );
    final store = _MemorySessionStore()..value = session;
    final repository = AuthRepository(
      api: _RefreshAuthApi(
        environment: environment,
        result: (_) =>
            throw const ApiFailure(message: '刷新凭证无效', statusCode: 401),
      ),
      sessionStore: store,
      clock: () => DateTime.utc(2026, 7, 29, 10),
    );

    final restored = await repository.ensureValid(session);

    expect(restored, isNull);
    expect(store.value, isNull);
  });
}
