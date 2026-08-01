import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/api_failure.dart';
import '../../../core/network/authenticated_api_client_provider.dart';
import '../../auth/application/auth_controller.dart';
import '../data/image_pipeline.dart';
import '../data/media_upload_api.dart';
import '../data/media_upload_task_store.dart';
import '../domain/media_upload_models.dart';

class MediaUploadCoordinator {
  MediaUploadCoordinator(
    this.ownerUserId,
    this._picker,
    this._preparer,
    this._api,
    this._uploader,
    this._store, {
    Uuid? uuid,
    DateTime Function()? now,
  }) : _uuid = uuid ?? const Uuid(),
       _now = now ?? (() => DateTime.now().toUtc());

  final String ownerUserId;
  final MediaImagePicker _picker;
  final MediaImagePreparer _preparer;
  final MediaUploadApi _api;
  final ObjectUploader _uploader;
  final MediaUploadTaskStore _store;
  final Uuid _uuid;
  final DateTime Function() _now;
  final Map<String, Future<MediaUploadTask>> _inFlight = {};

  Future<MediaUploadTask?> pickAndUpload({
    required MediaPurpose purpose,
    required MediaImageSource source,
  }) async {
    final selected = await _picker.pick(source);
    if (selected == null) return null;
    final image = await _preparer.prepare(selected, purpose);
    return enqueuePrepared(purpose: purpose, image: image);
  }

  Future<MediaUploadTask> enqueuePrepared({
    required MediaPurpose purpose,
    required PreparedImage image,
  }) async {
    final now = _now();
    final task = MediaUploadTask.fromPrepared(
      taskId: _uuid.v4(),
      ownerUserId: ownerUserId,
      purpose: purpose,
      image: image,
      createIdempotencyKey: _uuid.v4(),
      completeIdempotencyKey: _uuid.v4(),
      now: now,
    );
    await _store.write(task);
    return resume(task);
  }

  Future<List<MediaUploadTask>> resumePending() async {
    final tasks = await _store.readForOwner(ownerUserId);
    final resumed = <MediaUploadTask>[];
    for (final task in tasks.where((task) => task.status.canResume)) {
      resumed.add(await resume(task));
    }
    return resumed;
  }

  Future<MediaUploadTask> resume(MediaUploadTask task) async {
    _requireOwner(task);
    return _inFlight.putIfAbsent(task.taskId, () async {
      try {
        return await _process(task, renewedTicket: false);
      } finally {
        _inFlight.remove(task.taskId);
      }
    });
  }

  Future<MediaUploadTask> refreshProcessing(MediaUploadTask task) async {
    _requireOwner(task);
    final mediaId = task.mediaId;
    if (mediaId == null) return resume(task);
    try {
      final asset = await _api.loadMedia(
        mediaId,
        ownerUserId: task.ownerUserId,
      );
      final nextStatus = switch (asset.status) {
        'ready' => MediaUploadStatus.ready,
        'failed' || 'expired' => MediaUploadStatus.failed,
        _ => MediaUploadStatus.processing,
      };
      final updated = task.copyWith(
        status: nextStatus,
        updatedAt: _now(),
        errorMessage: nextStatus == MediaUploadStatus.failed
            ? '图片处理失败，请重新选择'
            : null,
        clearError: nextStatus != MediaUploadStatus.failed,
      );
      await _store.write(updated);
      return updated;
    } catch (error) {
      return _pause(task, error);
    }
  }

  Future<MediaUploadTask> waitUntilReady(
    MediaUploadTask task, {
    Duration timeout = const Duration(seconds: 45),
    Duration pollInterval = const Duration(milliseconds: 600),
  }) async {
    _requireOwner(task);
    var current = task;
    final pollCount = timeout.inMilliseconds ~/ pollInterval.inMilliseconds;
    for (
      var index = 0;
      current.status == MediaUploadStatus.processing && index < pollCount;
      index++
    ) {
      await Future<void>.delayed(pollInterval);
      current = await refreshProcessing(current);
    }
    if (current.status != MediaUploadStatus.processing) return current;
    return _pause(current, '图片处理时间较长，稍后可继续');
  }

  Future<MediaUploadTask> _process(
    MediaUploadTask initial, {
    required bool renewedTicket,
  }) async {
    if (initial.mediaId != null) return refreshProcessing(initial);
    if (!await File(initial.localPath).exists()) {
      return _fail(initial, '待上传图片已被系统清理，请重新选择');
    }

    var task = initial.copyWith(
      attempts: initial.attempts + 1,
      updatedAt: _now(),
      clearError: true,
    );
    await _store.write(task);

    try {
      var ticket = task.ticket;
      if (ticket == null || !ticket.isUsableAt(_now())) {
        if (ticket != null) {
          task = _renewTicketIdentity(task);
        }
        task = task.copyWith(
          status: MediaUploadStatus.requestingTicket,
          updatedAt: _now(),
          clearTicket: true,
          clearEtag: true,
        );
        await _store.write(task);
        ticket = await _api.createUpload(
          task,
          idempotencyKey: task.createIdempotencyKey,
        );
        task = task.copyWith(
          ticket: ticket,
          status: MediaUploadStatus.uploading,
          updatedAt: _now(),
        );
        await _store.write(task);
      }

      var etag = task.etag;
      if (etag == null) {
        task = task.copyWith(
          status: MediaUploadStatus.uploading,
          updatedAt: _now(),
        );
        await _store.write(task);
        try {
          etag = await _uploader.upload(
            file: File(task.localPath),
            ticket: ticket,
          );
        } on ApiFailure catch (error) {
          if (!renewedTicket && error.statusCode == 403) {
            final renewed = _renewTicketIdentity(task);
            await _store.write(renewed);
            return _process(renewed, renewedTicket: true);
          }
          rethrow;
        }
        task = task.copyWith(
          etag: etag,
          status: MediaUploadStatus.confirming,
          updatedAt: _now(),
        );
        await _store.write(task);
      }

      final asset = await _api.completeUpload(
        task,
        uploadId: ticket.uploadId,
        etag: etag,
        idempotencyKey: task.completeIdempotencyKey,
      );
      final completed = task.copyWith(
        mediaId: asset.mediaId,
        status: asset.status == 'ready'
            ? MediaUploadStatus.ready
            : MediaUploadStatus.processing,
        updatedAt: _now(),
        clearError: true,
      );
      await _store.write(completed);
      await _deleteLocalFile(completed.localPath);
      return completed;
    } on ApiFailure catch (error) {
      if (!renewedTicket && error.code == 'MEDIA_UPLOAD_EXPIRED') {
        final renewed = _renewTicketIdentity(task);
        await _store.write(renewed);
        return _process(renewed, renewedTicket: true);
      }
      if (_isPermanent(error)) {
        return _fail(task, error.message);
      }
      return _pause(task, error);
    } catch (error) {
      return _pause(task, error);
    }
  }

  MediaUploadTask _renewTicketIdentity(MediaUploadTask task) => task.copyWith(
    createIdempotencyKey: _uuid.v4(),
    completeIdempotencyKey: _uuid.v4(),
    status: MediaUploadStatus.prepared,
    updatedAt: _now(),
    clearTicket: true,
    clearEtag: true,
    clearError: true,
  );

  bool _isPermanent(ApiFailure error) =>
      error.statusCode == 400 ||
      error.statusCode == 413 ||
      error.statusCode == 415 ||
      error.statusCode == 422;

  Future<MediaUploadTask> _pause(MediaUploadTask task, Object error) async {
    final paused = task.copyWith(
      status: MediaUploadStatus.paused,
      updatedAt: _now(),
      errorMessage: _message(error),
    );
    await _store.write(paused);
    return paused;
  }

  Future<MediaUploadTask> _fail(MediaUploadTask task, String message) async {
    final failed = task.copyWith(
      status: MediaUploadStatus.failed,
      updatedAt: _now(),
      errorMessage: message,
    );
    await _store.write(failed);
    return failed;
  }

  String _message(Object error) => switch (error) {
    ApiFailure failure => failure.message,
    _ => '上传暂时中断，联网后可继续',
  };

  Future<void> _deleteLocalFile(String localPath) async {
    final file = File(localPath);
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // The upload is already safely stored in COS; cleanup can be retried later.
    }
  }

  void _requireOwner(MediaUploadTask task) {
    if (task.ownerUserId == ownerUserId) return;
    throw MediaUploadOwnerMismatch(
      expectedOwnerUserId: ownerUserId,
      actualOwnerUserId: task.ownerUserId,
    );
  }
}

final mediaImagePickerProvider = Provider<MediaImagePicker>(
  (_) => SystemMediaImagePicker(),
);

final mediaImagePreparerProvider = Provider<MediaImagePreparer>(
  (_) => DefaultMediaImagePreparer(),
);

final mediaUploadTaskStoreProvider = Provider<MediaUploadTaskStore>(
  (_) => FileMediaUploadTaskStore(),
);

final mediaUploadApiProvider = Provider<MediaUploadApi>((ref) {
  return HttpMediaUploadApi(ref.watch(authenticatedApiClientProvider));
});

final objectUploaderProvider = Provider<ObjectUploader>(
  (_) => DioObjectUploader(),
);

final mediaUploadCoordinatorProvider =
    Provider.autoDispose<MediaUploadCoordinator>((ref) {
      final ownerUserId = ref.watch(
        authControllerProvider.select((state) => state.session?.userId),
      );
      if (ownerUserId == null) {
        throw StateError('Media upload requires an authenticated account');
      }
      return MediaUploadCoordinator(
        ownerUserId,
        ref.watch(mediaImagePickerProvider),
        ref.watch(mediaImagePreparerProvider),
        ref.watch(mediaUploadApiProvider),
        ref.watch(objectUploaderProvider),
        ref.watch(mediaUploadTaskStoreProvider),
      );
    });

final mediaUploadRecoveryProvider =
    FutureProvider.autoDispose<List<MediaUploadTask>>((ref) async {
      final ownerUserId = ref.watch(
        authControllerProvider.select((state) => state.session?.userId),
      );
      if (ownerUserId == null) return const [];
      return ref.watch(mediaUploadCoordinatorProvider).resumePending();
    });
