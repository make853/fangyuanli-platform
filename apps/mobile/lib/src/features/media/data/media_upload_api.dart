import 'dart:io';

import 'package:dio/dio.dart';

import '../../../core/network/api_failure.dart';
import '../../../core/network/authenticated_api_client.dart';
import '../domain/media_upload_models.dart';

abstract interface class MediaUploadApi {
  Future<MediaUploadTicket> createUpload(
    MediaUploadTask task, {
    required String idempotencyKey,
  });

  Future<MediaAsset> completeUpload(
    MediaUploadTask task, {
    required String uploadId,
    required String etag,
    required String idempotencyKey,
  });

  Future<MediaAsset> loadMedia(String mediaId);
}

class HttpMediaUploadApi implements MediaUploadApi {
  const HttpMediaUploadApi(this._client);

  final AuthenticatedApiClient _client;

  @override
  Future<MediaUploadTicket> createUpload(
    MediaUploadTask task, {
    required String idempotencyKey,
  }) async {
    final envelope = await _client.post(
      '/media/uploads',
      idempotencyKey: idempotencyKey,
      data: {
        'purpose': task.purpose.wireValue,
        'mediaType': 'image',
        'fileName': task.fileName,
        'contentType': task.contentType,
        'bytes': task.bytes,
        'sha256': task.sha256,
        'durationMs': null,
        'width': task.width,
        'height': task.height,
      },
    );
    return MediaUploadTicket.fromJson(_data(envelope));
  }

  @override
  Future<MediaAsset> completeUpload(
    MediaUploadTask task, {
    required String uploadId,
    required String etag,
    required String idempotencyKey,
  }) async {
    final envelope = await _client.post(
      '/media/uploads/$uploadId/complete',
      idempotencyKey: idempotencyKey,
      data: {'etag': etag, 'bytes': task.bytes, 'sha256': task.sha256},
    );
    return MediaAsset.fromJson(_data(envelope));
  }

  @override
  Future<MediaAsset> loadMedia(String mediaId) async {
    final envelope = await _client.get('/media/$mediaId');
    return MediaAsset.fromJson(_data(envelope));
  }

  Map<String, dynamic> _data(Map<String, dynamic> envelope) {
    final data = envelope['data'];
    if (data is! Map<String, dynamic>) {
      throw const ApiFailure(message: '服务器返回的数据格式不正确');
    }
    return data;
  }
}

abstract interface class ObjectUploader {
  Future<String> upload({
    required File file,
    required MediaUploadTicket ticket,
  });
}

class DioObjectUploader implements ObjectUploader {
  DioObjectUploader({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 20),
              sendTimeout: const Duration(minutes: 2),
              receiveTimeout: const Duration(seconds: 30),
            ),
          );

  final Dio _dio;

  @override
  Future<String> upload({
    required File file,
    required MediaUploadTicket ticket,
  }) async {
    if (ticket.method != 'PUT') {
      throw const ApiFailure(message: '暂不支持服务器返回的上传方式');
    }
    if (!await file.exists()) {
      throw const ApiFailure(message: '待上传图片已经丢失，请重新选择');
    }
    final length = await file.length();
    try {
      final response = await _dio.put<Object?>(
        ticket.uploadUrl.toString(),
        data: file.openRead(),
        options: Options(
          headers: {...ticket.headers, Headers.contentLengthHeader: length},
          responseType: ResponseType.plain,
          validateStatus: (status) =>
              status != null && status >= 200 && status < 300,
        ),
      );
      final etag = response.headers.value('etag')?.trim();
      if (etag == null || etag.isEmpty) {
        throw const ApiFailure(message: '存储服务没有返回文件校验标识');
      }
      return etag;
    } on DioException catch (error) {
      throw ApiFailure.fromDio(error);
    }
  }
}
