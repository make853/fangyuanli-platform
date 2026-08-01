import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../domain/media_upload_models.dart';

abstract interface class MediaUploadTaskStore {
  Future<List<MediaUploadTask>> readAll();
  Future<void> write(MediaUploadTask task);
  Future<void> remove(String taskId);
}

class FileMediaUploadTaskStore implements MediaUploadTaskStore {
  FileMediaUploadTaskStore({Future<Directory> Function()? directoryLoader})
    : _directoryLoader =
          directoryLoader ??
          (() async {
            final support = await getApplicationSupportDirectory();
            return Directory(path.join(support.path, 'fangyuanli', 'media'));
          });

  final Future<Directory> Function() _directoryLoader;
  Future<void> _writeQueue = Future.value();

  @override
  Future<List<MediaUploadTask>> readAll() async {
    await _writeQueue;
    final file = await _taskFile();
    if (!await file.exists()) return const [];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(MediaUploadTask.fromJson)
          .toList(growable: false);
    } on FormatException {
      await _quarantine(file);
      return const [];
    } on TypeError {
      await _quarantine(file);
      return const [];
    }
  }

  @override
  Future<void> write(MediaUploadTask task) => _serialize(() async {
    final tasks = await _readUnlocked();
    final index = tasks.indexWhere((item) => item.taskId == task.taskId);
    if (index == -1) {
      tasks.add(task);
    } else {
      tasks[index] = task;
    }
    await _writeUnlocked(tasks);
  });

  @override
  Future<void> remove(String taskId) => _serialize(() async {
    final tasks = await _readUnlocked();
    tasks.removeWhere((task) => task.taskId == taskId);
    await _writeUnlocked(tasks);
  });

  Future<void> _serialize(Future<void> Function() operation) {
    final next = _writeQueue.then((_) => operation());
    _writeQueue = next.catchError((_) {});
    return next;
  }

  Future<List<MediaUploadTask>> _readUnlocked() async {
    final file = await _taskFile();
    if (!await file.exists()) return [];
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! List) return [];
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(MediaUploadTask.fromJson)
        .toList();
  }

  Future<void> _writeUnlocked(List<MediaUploadTask> tasks) async {
    final file = await _taskFile();
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode(tasks.map((task) => task.toJson()).toList()),
      flush: true,
    );
    await temporary.rename(file.path);
  }

  Future<File> _taskFile() async {
    final directory = await _directoryLoader();
    return File(path.join(directory.path, 'upload_tasks.v1.json'));
  }

  Future<void> _quarantine(File file) async {
    if (!await file.exists()) return;
    final broken = File('${file.path}.broken');
    if (await broken.exists()) await broken.delete();
    await file.rename(broken.path);
  }
}
