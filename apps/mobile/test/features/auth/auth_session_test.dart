import 'package:fangyuanli_mobile/src/features/auth/domain/auth_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final session = AuthSession(
    accessToken: 'access',
    accessTokenExpiresAt: DateTime.utc(2026, 7, 29, 10),
    refreshToken: 'refresh',
    refreshTokenExpiresAt: DateTime.utc(2026, 8, 29, 10),
    deviceId: 'device-id',
    userId: 'user-id',
    isNewUser: true,
  );

  test('会话可以安全序列化和还原', () {
    final decoded = AuthSession.decode(session.encode());

    expect(decoded.accessToken, session.accessToken);
    expect(decoded.refreshToken, session.refreshToken);
    expect(decoded.userId, session.userId);
    expect(decoded.isNewUser, isTrue);
  });

  test('访问令牌在一分钟内到期时应刷新', () {
    expect(
      session.accessTokenNeedsRefresh(DateTime.utc(2026, 7, 29, 9, 59, 30)),
      isTrue,
    );
    expect(
      session.accessTokenNeedsRefresh(DateTime.utc(2026, 7, 29, 9, 30)),
      isFalse,
    );
  });
}
