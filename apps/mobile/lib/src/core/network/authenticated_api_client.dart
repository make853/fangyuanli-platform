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

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) {
    return _request(
      (options) => _dio.get<Map<String, dynamic>>(
        path,
        queryParameters: queryParameters,
        options: options,
      ),
    );
  }

  Future<Map<String, dynamic>> post(
    String path, {
    Object? data,
    bool idempotent = false,
  }) {
    return _request(
      (options) => _dio.post<Map<String, dynamic>>(
        path,
        data: data,
        options: idempotent
            ? options.copyWith(
                headers: {...?options.headers, 'idempotency-key': _uuid.v4()},
              )
            : options,
      ),
    );
  }

  Future<Map<String, dynamic>> _request(
    Future<Response<Map<String, dynamic>>> Function(Options options) send, {
    bool retried = false,
  }) async {
    final session = await loadSession(forceRefresh: false);
    if (session == null) {
      throw const ApiFailure(
        message: '登录状态已失效，请重新登录',
        code: 'AUTH_REQUIRED',
        statusCode: 401,
      );
    }

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
          return _request(send, retried: true);
        }
      }
      throw ApiFailure.fromDio(error);
    }
  }

  Options _options(AuthSession session) {
    return Options(
      headers: {
        'authorization': 'Bearer ${session.accessToken}',
        'x-device-id': session.deviceId,
      },
    );
  }
}
