import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/network/api_failure.dart';
import '../domain/auth_session.dart';

class SmsChallenge {
  const SmsChallenge({
    required this.verificationId,
    required this.expiresAt,
    required this.resendAfterSeconds,
  });

  factory SmsChallenge.fromJson(Map<String, dynamic> json) {
    return SmsChallenge(
      verificationId: json['verificationId'] as String,
      expiresAt: DateTime.parse(json['expiresAt'] as String).toUtc(),
      resendAfterSeconds: json['resendAfterSeconds'] as int,
    );
  }

  final String verificationId;
  final DateTime expiresAt;
  final int resendAfterSeconds;
}

class AuthApi {
  AuthApi({required AppEnvironment environment, Dio? dio, Uuid? uuid})
    : _uuid = uuid ?? const Uuid(),
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
  final Uuid _uuid;

  Future<SmsChallenge> sendLoginCode(String phoneNumber) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/auth/sms/send',
        data: {
          'countryCode': '+86',
          'phoneNumber': phoneNumber,
          'purpose': 'login',
        },
      );
      return SmsChallenge.fromJson(_data(response));
    } on DioException catch (error) {
      throw ApiFailure.fromDio(error);
    }
  }

  Future<AuthSession> verifyLoginCode({
    required SmsChallenge challenge,
    required String code,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/auth/sms/verify',
        options: Options(headers: {'idempotency-key': _uuid.v4()}),
        data: {
          'verificationId': challenge.verificationId,
          'code': code,
          'device': {'platform': 'ios', 'deviceName': '方圆里 iPhone'},
        },
      );
      return AuthSession.fromJson(_data(response));
    } on DioException catch (error) {
      throw ApiFailure.fromDio(error);
    }
  }

  Future<AuthSession> refresh(AuthSession session) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {
          'deviceId': session.deviceId,
          'refreshToken': session.refreshToken,
        },
      );
      return AuthSession.fromJson(_data(response));
    } on DioException catch (error) {
      throw ApiFailure.fromDio(error);
    }
  }

  Future<void> logout(AuthSession session) async {
    try {
      await _dio.post<void>(
        '/auth/logout',
        options: Options(
          headers: {
            'authorization': 'Bearer ${session.accessToken}',
            'x-device-id': session.deviceId,
          },
        ),
      );
    } on DioException catch (error) {
      throw ApiFailure.fromDio(error);
    }
  }

  Map<String, dynamic> _data(Response<Map<String, dynamic>> response) {
    final data = response.data?['data'];
    if (data is! Map<String, dynamic>) {
      throw const ApiFailure(message: '服务器返回的数据格式不正确');
    }
    return data;
  }
}
