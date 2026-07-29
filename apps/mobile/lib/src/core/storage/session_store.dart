import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../features/auth/domain/auth_session.dart';

abstract interface class SessionStore {
  Future<AuthSession?> read();
  Future<void> write(AuthSession session);
  Future<void> clear();
}

class SecureSessionStore implements SessionStore {
  SecureSessionStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _sessionKey = 'fangyuanli.auth.session.v1';
  final FlutterSecureStorage _storage;

  @override
  Future<AuthSession?> read() async {
    final value = await _storage.read(key: _sessionKey);
    if (value == null) return null;
    try {
      return AuthSession.decode(value);
    } on FormatException {
      await clear();
      return null;
    } on TypeError {
      await clear();
      return null;
    }
  }

  @override
  Future<void> write(AuthSession session) {
    return _storage.write(key: _sessionKey, value: session.encode());
  }

  @override
  Future<void> clear() => _storage.delete(key: _sessionKey);
}
