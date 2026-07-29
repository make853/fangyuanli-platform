import 'package:dio/dio.dart';

class ApiFailure implements Exception {
  const ApiFailure({required this.message, this.code, this.statusCode});

  factory ApiFailure.fromDio(DioException error) {
    final responseData = error.response?.data;
    final errorData = responseData is Map<String, dynamic>
        ? responseData['error']
        : null;
    final serverMessage = errorData is Map<String, dynamic>
        ? errorData['message'] as String?
        : null;
    final serverCode = errorData is Map<String, dynamic>
        ? errorData['code'] as String?
        : null;

    return ApiFailure(
      message: serverMessage ?? _fallbackMessage(error),
      code: serverCode,
      statusCode: error.response?.statusCode,
    );
  }

  final String message;
  final String? code;
  final int? statusCode;

  static String _fallbackMessage(DioException error) {
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout => '网络连接超时，请稍后重试',
      DioExceptionType.connectionError => '暂时无法连接服务器',
      _ => '操作失败，请稍后重试',
    };
  }

  @override
  String toString() => message;
}
