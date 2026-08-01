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
    ).readForOwner('user-1')).single;

    expect(restored.taskId, task.taskId);
    expect(restored.ownerUserId, 'user-1');
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

    final tasks = await store.readForOwner('user-1');
    expect(tasks, hasLength(1));
    expect(tasks.single.status, MediaUploadStatus.paused);
  });

  test('keeps durable upload tasks isolated by account', () async {
    final store = FileMediaUploadTaskStore(
      directoryLoader: () async => directory,
    );
    await store.write(_task(ownerUserId: 'user-1'));
    await store.write(_task(ownerUserId: 'user-2'));

    final firstAccount = await store.readForOwner('user-1');
    final secondAccount = await store.readForOwner('user-2');

    expect(firstAccount.map((task) => task.ownerUserId), ['user-1']);
    expect(secondAccount.map((task) => task.ownerUserId), ['user-2']);

    await store.remove(ownerUserId: 'user-1', taskId: 'task-1');
    expect(await store.readForOwner('user-1'), isEmpty);
    expect(await store.readForOwner('user-2'), hasLength(1));
  });

  test('does not restore legacy tasks without an account owner', () async {
    final legacy = File('${directory.path}/upload_tasks.v1.json');
    await legacy.writeAsString('[{"taskId":"legacy-task"}]', flush: true);

    final restored = await FileMediaUploadTaskStore(
      directoryLoader: () async => directory,
    ).readForOwner('user-1');

    expect(restored, isEmpty);
    expect(await legacy.exists(), isTrue);
  });
}

MediaUploadTask _task({String ownerUserId = 'user-1'}) =>
    MediaUploadTask.fromPrepared(
      taskId: 'task-1',
      ownerUserId: ownerUserId,
      purpose: MediaPurpose.avatar,
      image: const PreparedImage(
        localPath: '/tmp/prepared.jpg',
        fileName: 'prepared.jpg',
        contentType: 'image/jpeg',
        bytes: 4,
        sha256:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        width: 1200,
        height: 800,
      ),
      createIdempotencyKey: 'create-1',
      completeIdempotencyKey: 'complete-1',
      now: DateTime.utc(2026, 8, 1, 10),
    );
