import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import '../../features/auth/domain/auth_session.dart';
import '../config/app_environment.dart';
import 'api_failure.dart';

typedef SessionLoader = Future<AuthSession?> Function({bool forceRefresh});

class AuthenticatedApiClient {
  AuthenticatedApiClient({
    required AppEnvironment environment,
    required this.loadSession,
    Dio? dio,
    Uuid? uuid,
  }) : _uuid = uuid ?? const Uuid(),
       _dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: environment.apiBaseUrl,
               connectTimeout: const Duration(seconds: 12),
               receiveTimeout: const Duration(seconds: 12),
               sendTimeout: const Duration(seconds: 12),
               headers: const {'accept': 'application/json'},
             ),
           );

  final Dio _dio;
  final SessionLoader loadSession;
  final Uuid _uuid;

  void close() => _dio.close(force: true);

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    String? expectedUserId,
  }) {
    return _request(
      (options) => _dio.get<Map<String, dynamic>>(
        path,
        queryParameters: queryParameters,
        options: options,
      ),
      expectedUserId: expectedUserId,
    );
  }

  Future<Map<String, dynamic>> post(
    String path, {
    Object? data,
    bool idempotent = false,
    String? idempotencyKey,
    String? expectedUserId,
  }) {
    final resolvedIdempotencyKey = _resolveIdempotencyKey(
      idempotent: idempotent,
      explicitKey: idempotencyKey,
    );
    return _request(
      (options) => _dio.post<Map<String, dynamic>>(
        path,
        data: data,
        options: _withIdempotency(options, resolvedIdempotencyKey),
      ),
      expectedUserId: expectedUserId,
    );
  }

  Future<Map<String, dynamic>> patch(
    String path, {
    Object? data,
    bool idempotent = false,
    String? idempotencyKey,
    String? expectedUserId,
  }) {
    final resolvedIdempotencyKey = _resolveIdempotencyKey(
      idempotent: idempotent,
      explicitKey: idempotencyKey,
    );
    return _request(
      (options) => _dio.patch<Map<String, dynamic>>(
        path,
        data: data,
        options: _withIdempotency(options, resolvedIdempotencyKey),
      ),
      expectedUserId: expectedUserId,
    );
  }

  Future<Map<String, dynamic>> put(
    String path, {
    Object? data,
    bool idempotent = false,
    String? idempotencyKey,
    String? expectedUserId,
  }) {
    final resolvedIdempotencyKey = _resolveIdempotencyKey(
      idempotent: idempotent,
      explicitKey: idempotencyKey,
    );
    return _request(
      (options) => _dio.put<Map<String, dynamic>>(
        path,
        data: data,
        options: _withIdempotency(options, resolvedIdempotencyKey),
      ),
      expectedUserId: expectedUserId,
    );
  }

  Future<Map<String, dynamic>> delete(
    String path, {
    bool idempotent = false,
    String? idempotencyKey,
    String? expectedUserId,
  }) {
    final resolvedIdempotencyKey = _resolveIdempotencyKey(
      idempotent: idempotent,
      explicitKey: idempotencyKey,
    );
    return _request(
      (options) => _dio.delete<Map<String, dynamic>>(
        path,
        options: _withIdempotency(options, resolvedIdempotencyKey),
      ),
      expectedUserId: expectedUserId,
    );
  }

  Future<void> deleteWithoutResponse(
    String path, {
    bool idempotent = false,
    String? idempotencyKey,
    String? expectedUserId,
  }) async {
    final resolvedIdempotencyKey = _resolveIdempotencyKey(
      idempotent: idempotent,
      explicitKey: idempotencyKey,
    );
    await _voidRequest(
      (options) => _dio.delete<void>(
        path,
        options: _withIdempotency(options, resolvedIdempotencyKey),
      ),
      expectedUserId: expectedUserId,
    );
  }

  Future<Map<String, dynamic>> _request(
    Future<Response<Map<String, dynamic>>> Function(Options options) send, {
    bool retried = false,
    String? expectedUserId,
  }) async {
    final session = await loadSession(forceRefresh: false);
    if (session == null) {
      throw const ApiFailure(
        message: '登录状态已失效，请重新登录',
        code: 'AUTH_REQUIRED',
        statusCode: 401,
      );
    }
    _requireExpectedUser(session, expectedUserId);

    try {
      final response = await send(_options(session));
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw const ApiFailure(message: '服务器返回的数据格式不正确');
      }
      return data;
    } on DioException catch (error) {
      if (!retried && error.response?.statusCode == 401) {
        final refreshed = await loadSession(forceRefresh: true);
        if (refreshed != null) {
          _requireExpectedUser(refreshed, expectedUserId);
          return _request(send, retried: true, expectedUserId: expectedUserId);
        }
      }
      throw ApiFailure.fromDio(error);
    }
  }

  Future<void> _voidRequest(
    Future<Response<void>> Function(Options options) send, {
    bool retried = false,
    String? expectedUserId,
  }) async {
    final session = await loadSession(forceRefresh: false);
    if (session == null) {
      throw const ApiFailure(
        message: '登录状态已失效，请重新登录',
        code: 'AUTH_REQUIRED',
        statusCode: 401,
      );
    }
    _requireExpectedUser(session, expectedUserId);

    try {
      await send(_options(session));
    } on DioException catch (error) {
      if (!retried && error.response?.statusCode == 401) {
        final refreshed = await loadSession(forceRefresh: true);
        if (refreshed != null) {
          _requireExpectedUser(refreshed, expectedUserId);
          return _voidRequest(
            send,
            retried: true,
            expectedUserId: expectedUserId,
          );
        }
      }
      throw ApiFailure.fromDio(error);
    }
  }

  Options _withIdempotency(Options options, String? idempotencyKey) {
    if (idempotencyKey == null) return options;
    return options.copyWith(
      headers: {...?options.headers, 'idempotency-key': idempotencyKey},
    );
  }

  String? _resolveIdempotencyKey({
    required bool idempotent,
    required String? explicitKey,
  }) {
    final trimmed = explicitKey?.trim();
    if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    return idempotent ? _uuid.v4() : null;
  }

  Options _options(AuthSession session) {
    return Options(
      headers: {
        'authorization': 'Bearer ${session.accessToken}',
        'x-device-id': session.deviceId,
      },
    );
  }

  void _requireExpectedUser(AuthSession session, String? expectedUserId) {
    if (expectedUserId == null || session.userId == expectedUserId) return;
    throw const ApiFailure(
      message: '账号已经切换，请使用原账号继续此操作',
      code: 'AUTH_ACCOUNT_CHANGED',
      statusCode: 409,
    );
  }
}
