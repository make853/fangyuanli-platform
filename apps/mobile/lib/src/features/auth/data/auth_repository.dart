import '../../../core/storage/session_store.dart';
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
    return ensureValid(session);
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
    } catch (_) {
      await sessionStore.clear();
      return null;
    }
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
