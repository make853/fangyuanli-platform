import 'dart:io';

import 'package:fangyuanli_mobile/src/core/network/api_failure.dart';
import 'package:fangyuanli_mobile/src/features/media/application/media_upload_coordinator.dart';
import 'package:fangyuanli_mobile/src/features/media/data/image_pipeline.dart';
import 'package:fangyuanli_mobile/src/features/media/data/media_upload_api.dart';
import 'package:fangyuanli_mobile/src/features/media/data/media_upload_task_store.dart';
import 'package:fangyuanli_mobile/src/features/media/domain/media_upload_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  late Directory temporary;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('fangyuanli-media-test-');
  });

  tearDown(() async {
    if (await temporary.exists()) {
      await temporary.delete(recursive: true);
    }
  });

  test('uploads a prepared image and persists processing state', () async {
    final file = await _imageFile(temporary);
    final api = _FakeMediaApi();
    final uploader = _FakeObjectUploader();
    final store = _MemoryTaskStore();
    final coordinator = MediaUploadCoordinator(
      _ownerUserId,
      _UnusedPicker(),
      _UnusedPreparer(),
      api,
      uploader,
      store,
      now: () => _now,
    );

    final result = await coordinator.enqueuePrepared(
      purpose: MediaPurpose.avatar,
      image: _prepared(file),
    );

    expect(result.status, MediaUploadStatus.processing);
    expect(result.mediaId, 'media-1');
    expect(api.createKeys, [result.createIdempotencyKey]);
    expect(api.completeKeys, [result.completeIdempotencyKey]);
    expect(uploader.calls, 1);
    expect(await file.exists(), isFalse);
    expect((await store.readForOwner(_ownerUserId)).single.mediaId, 'media-1');
  });

  test('keeps the upload ticket and resumes after a network failure', () async {
    final file = await _imageFile(temporary);
    final api = _FakeMediaApi();
    final uploader = _FakeObjectUploader(
      errors: [const ApiFailure(message: '网络中断')],
    );
    final store = _MemoryTaskStore();
    final coordinator = MediaUploadCoordinator(
      _ownerUserId,
      _UnusedPicker(),
      _UnusedPreparer(),
      api,
      uploader,
      store,
      now: () => _now,
    );

    final paused = await coordinator.enqueuePrepared(
      purpose: MediaPurpose.post,
      image: _prepared(file),
    );
    expect(paused.status, MediaUploadStatus.paused);
    expect(paused.ticket, isNotNull);
    expect(await file.exists(), isTrue);

    final completed = await coordinator.resume(paused);
    expect(completed.status, MediaUploadStatus.processing);
    expect(api.createKeys, hasLength(1));
    expect(api.completeKeys, hasLength(1));
    expect(uploader.calls, 2);
    expect(completed.attempts, 2);
  });

  test('renews an expired upload ticket before retrying', () async {
    final file = await _imageFile(temporary);
    final api = _FakeMediaApi();
    final store = _MemoryTaskStore();
    final original =
        MediaUploadTask.fromPrepared(
          taskId: 'task-1',
          ownerUserId: _ownerUserId,
          purpose: MediaPurpose.background,
          image: _prepared(file),
          createIdempotencyKey: 'create-old',
          completeIdempotencyKey: 'complete-old',
          now: _now,
        ).copyWith(
          ticket: MediaUploadTicket(
            uploadId: 'expired-upload',
            method: 'PUT',
            uploadUrl: Uri.parse('https://storage.example/expired'),
            headers: const {'Content-Type': 'image/jpeg'},
            expiresAt: _now.subtract(const Duration(seconds: 1)),
          ),
        );
    await store.write(original);
    final coordinator = MediaUploadCoordinator(
      _ownerUserId,
      _UnusedPicker(),
      _UnusedPreparer(),
      api,
      _FakeObjectUploader(),
      store,
      now: () => _now,
    );

    final completed = await coordinator.resume(original);

    expect(completed.status, MediaUploadStatus.processing);
    expect(api.createKeys.single, isNot('create-old'));
    expect(api.completeKeys.single, isNot('complete-old'));
    expect(completed.ticket?.uploadId, 'upload-1');
  });

  test('marks a task as failed when its local file was removed', () async {
    final missing = File('${temporary.path}/missing.jpg');
    final store = _MemoryTaskStore();
    final coordinator = MediaUploadCoordinator(
      _ownerUserId,
      _UnusedPicker(),
      _UnusedPreparer(),
      _FakeMediaApi(),
      _FakeObjectUploader(),
      store,
      now: () => _now,
    );

    final result = await coordinator.enqueuePrepared(
      purpose: MediaPurpose.chat,
      image: _prepared(missing),
    );

    expect(result.status, MediaUploadStatus.failed);
    expect(result.errorMessage, contains('重新选择'));
  });

  test('never resumes a durable task owned by another account', () async {
    final file = await _imageFile(temporary);
    final otherAccountTask = MediaUploadTask.fromPrepared(
      taskId: 'other-account-task',
      ownerUserId: 'user-2',
      purpose: MediaPurpose.post,
      image: _prepared(file),
      createIdempotencyKey: 'create-other',
      completeIdempotencyKey: 'complete-other',
      now: _now,
    );
    final store = _MemoryTaskStore();
    await store.write(otherAccountTask);
    final coordinator = MediaUploadCoordinator(
      _ownerUserId,
      _UnusedPicker(),
      _UnusedPreparer(),
      _FakeMediaApi(),
      _FakeObjectUploader(),
      store,
      now: () => _now,
    );

    await expectLater(
      coordinator.resume(otherAccountTask),
      throwsA(isA<MediaUploadOwnerMismatch>()),
    );
    expect(await coordinator.resumePending(), isEmpty);
  });
}

final _now = DateTime.utc(2026, 8, 1, 10);
const _ownerUserId = 'user-1';

Future<File> _imageFile(Directory directory) async {
  final file = File('${directory.path}/prepared.jpg');
  await file.writeAsBytes([1, 2, 3, 4], flush: true);
  return file;
}

PreparedImage _prepared(File file) => PreparedImage(
  localPath: file.path,
  fileName: 'prepared.jpg',
  contentType: 'image/jpeg',
  bytes: 4,
  sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  width: 1200,
  height: 800,
);

class _UnusedPicker implements MediaImagePicker {
  @override
  Future<XFile?> pick(MediaImageSource source) => Future.value();
}

class _UnusedPreparer implements MediaImagePreparer {
  @override
  Future<PreparedImage> prepare(XFile source, MediaPurpose purpose) {
    throw UnimplementedError();
  }
}

class _FakeMediaApi implements MediaUploadApi {
  final List<String> createKeys = [];
  final List<String> completeKeys = [];

  @override
  Future<MediaUploadTicket> createUpload(
    MediaUploadTask task, {
    required String idempotencyKey,
  }) async {
    createKeys.add(idempotencyKey);
    return MediaUploadTicket(
      uploadId: 'upload-${createKeys.length}',
      method: 'PUT',
      uploadUrl: Uri.parse('https://storage.example/object'),
      headers: const {'Content-Type': 'image/jpeg'},
      expiresAt: _now.add(const Duration(minutes: 15)),
    );
  }

  @override
  Future<MediaAsset> completeUpload(
    MediaUploadTask task, {
    required String uploadId,
    required String etag,
    required String idempotencyKey,
  }) async {
    completeKeys.add(idempotencyKey);
    return const MediaAsset(mediaId: 'media-1', status: 'processing');
  }

  @override
  Future<MediaAsset> loadMedia(
    String mediaId, {
    required String ownerUserId,
  }) async => MediaAsset(mediaId: mediaId, status: 'ready');
}

class _FakeObjectUploader implements ObjectUploader {
  _FakeObjectUploader({List<Object>? errors}) : _errors = errors ?? [];

  final List<Object> _errors;
  int calls = 0;

  @override
  Future<String> upload({
    required File file,
    required MediaUploadTicket ticket,
  }) async {
    calls += 1;
    if (_errors.isNotEmpty) throw _errors.removeAt(0);
    return 'etag-1';
  }
}

class _MemoryTaskStore implements MediaUploadTaskStore {
  final Map<String, MediaUploadTask> _tasks = {};

  @override
  Future<List<MediaUploadTask>> readForOwner(String ownerUserId) async =>
      _tasks.values.where((task) => task.ownerUserId == ownerUserId).toList();

  @override
  Future<void> remove({
    required String ownerUserId,
    required String taskId,
  }) async {
    _tasks.remove('$ownerUserId:$taskId');
  }

  @override
  Future<void> write(MediaUploadTask task) async {
    _tasks['${task.ownerUserId}:${task.taskId}'] = task;
  }
}
