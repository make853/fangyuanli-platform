import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class RealtimeCursorStore {
  Future<String?> read(String userId);
  Future<void> write(String userId, String cursor);
  Future<void> clear(String userId);
}

class SecureRealtimeCursorStore implements RealtimeCursorStore {
  SecureRealtimeCursorStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _keyPrefix = 'fangyuanli.realtime.cursor.v1';
  final FlutterSecureStorage _storage;

  String _key(String userId) => '$_keyPrefix.$userId';

  @override
  Future<String?> read(String userId) => _storage.read(key: _key(userId));

  @override
  Future<void> write(String userId, String cursor) {
    return _storage.write(key: _key(userId), value: cursor);
  }

  @override
  Future<void> clear(String userId) => _storage.delete(key: _key(userId));
}
