import 'dart:io';

import 'package:fangyuanli_mobile/src/features/media/data/media_upload_task_store.dart';
import 'package:fangyuanli_mobile/src/features/media/domain/media_upload_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('fangyuanli-task-store-');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('persists enough upload state to resume after app restart', () async {
    final store = FileMediaUploadTaskStore(
      directoryLoader: () async => directory,
    );
    final task = _task().copyWith(
      status: MediaUploadStatus.uploading,
      ticket: MediaUploadTicket(
        uploadId: 'upload-1',
        method: 'PUT',
        uploadUrl: Uri.parse('https://storage.example/object'),
        headers: const {'Content-Type': 'image/jpeg'},
        expiresAt: DateTime.utc(2026, 8, 1, 10, 15),
      ),
    );

    await store.write(task);
    final restored = (await FileMediaUploadTaskStore(
      directoryLoader: () async => directory,
    ).readAll()).single;

    expect(restored.taskId, task.taskId);
    expect(restored.ticket?.uploadId, 'upload-1');
    expect(restored.createIdempotencyKey, 'create-1');
    expect(restored.completeIdempotencyKey, 'complete-1');
    expect(restored.status, MediaUploadStatus.uploading);
  });

  test('replaces an existing task instead of duplicating it', () async {
    final store = FileMediaUploadTaskStore(
      directoryLoader: () async => directory,
    );
    await store.write(_task());
    await store.write(_task().copyWith(status: MediaUploadStatus.paused));

    final tasks = await store.readAll();
    expect(tasks, hasLength(1));
    expect(tasks.single.status, MediaUploadStatus.paused);
  });
}

MediaUploadTask _task() => MediaUploadTask.fromPrepared(
  taskId: 'task-1',
  purpose: MediaPurpose.avatar,
  image: const PreparedImage(
    localPath: '/tmp/prepared.jpg',
    fileName: 'prepared.jpg',
    contentType: 'image/jpeg',
    bytes: 4,
    sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    width: 1200,
    height: 800,
  ),
  createIdempotencyKey: 'create-1',
  completeIdempotencyKey: 'complete-1',
  now: DateTime.utc(2026, 8, 1, 10),
);
