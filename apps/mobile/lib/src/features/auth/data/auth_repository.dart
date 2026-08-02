import '../../../core/storage/session_store.dart';
import '../../../core/network/api_failure.dart';
import '../domain/auth_session.dart';
import 'auth_api.dart';

class AuthRepository {
  AuthRepository({
    required this.api,
    required this.sessionStore,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AuthApi api;
  final SessionStore sessionStore;
  final DateTime Function() _clock;

  Future<AuthSession?> restore() async {
    final session = await sessionStore.read();
    if (session == null) return null;
    if (session.refreshTokenExpired(_clock())) {
      await sessionStore.clear();
      return null;
    }

    // Cold start must not wait for the network. The refresh token is the
    // durable login credential; access-token renewal happens lazily when a
    // request needs it. This lets cached screens render immediately offline.
    return session;
  }

  Future<AuthSession?> ensureValid(
    AuthSession session, {
    bool forceRefresh = false,
  }) async {
    if (session.refreshTokenExpired(_clock())) {
      await sessionStore.clear();
      return null;
    }
    if (!forceRefresh && !session.accessTokenNeedsRefresh(_clock())) {
      return session;
    }

    try {
      final refreshed = await api.refresh(session);
      await sessionStore.write(refreshed);
      return refreshed;
    } on ApiFailure catch (error) {
      if (_credentialsWereRejected(error)) {
        await sessionStore.clear();
        return null;
      }

      // Connectivity and server availability are not logout signals. Keep the
      // refresh credential so local snapshots remain available and a later
      // request can retry renewal after the network recovers.
      return session;
    }
  }

  static bool _credentialsWereRejected(ApiFailure error) {
    return error.code == 'AUTH_REFRESH_INVALID' ||
        error.statusCode == 401 ||
        error.statusCode == 403;
  }

  Future<SmsChallenge> sendLoginCode(String phoneNumber) {
    return api.sendLoginCode(phoneNumber);
  }

  Future<AuthSession> verifyLoginCode({
    required SmsChallenge challenge,
    required String code,
  }) async {
    final session = await api.verifyLoginCode(challenge: challenge, code: code);
    await sessionStore.write(session);
    return session;
  }

  Future<void> logout(AuthSession session) async {
    try {
      await api.logout(session);
    } finally {
      await sessionStore.clear();
    }
  }
}
