import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../domain/media_upload_models.dart';

enum MediaImageSource { gallery, camera }

abstract interface class MediaImagePicker {
  Future<XFile?> pick(MediaImageSource source);
}

class SystemMediaImagePicker implements MediaImagePicker {
  SystemMediaImagePicker({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<XFile?> pick(MediaImageSource source) => _picker.pickImage(
    source: source == MediaImageSource.camera
        ? ImageSource.camera
        : ImageSource.gallery,
    imageQuality: 100,
    requestFullMetadata: false,
  );
}

abstract interface class MediaImagePreparer {
  Future<PreparedImage> prepare(XFile source, MediaPurpose purpose);
}

class DefaultMediaImagePreparer implements MediaImagePreparer {
  DefaultMediaImagePreparer({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  static const _serverLimitBytes = 20 * 1024 * 1024;
  static const _preferredMaxBytes = 6 * 1024 * 1024;

  final Uuid _uuid;

  @override
  Future<PreparedImage> prepare(XFile source, MediaPurpose purpose) async {
    final sourceFile = File(source.path);
    if (!await sourceFile.exists()) {
      throw const FileSystemException('选择的图片已经不可用');
    }

    final sourceBytes = await sourceFile.readAsBytes();
    if (sourceBytes.isEmpty) {
      throw const FormatException('不能上传空图片');
    }
    final sourceSize = await _decodeSize(sourceBytes);
    final longSide = sourceSize.$1 > sourceSize.$2
        ? sourceSize.$1
        : sourceSize.$2;
    final preferredLongSide = purpose == MediaPurpose.avatar ? 1600 : 2560;
    final sourceType = _contentType(source.name);
    final canKeepOriginal =
        sourceType != null &&
        sourceBytes.length <= _preferredMaxBytes &&
        longSide <= preferredLongSide;

    final directory = await _pendingDirectory();
    final taskName = _uuid.v4();
    late File preparedFile;
    late String contentType;

    if (canKeepOriginal) {
      final extension = path.extension(source.name).toLowerCase();
      preparedFile = File(path.join(directory.path, '$taskName$extension'));
      await preparedFile.writeAsBytes(sourceBytes, flush: true);
      contentType = sourceType;
    } else {
      preparedFile = File(path.join(directory.path, '$taskName.jpg'));
      await _compress(
        sourcePath: source.path,
        targetPath: preparedFile.path,
        sourceWidth: sourceSize.$1,
        sourceHeight: sourceSize.$2,
        preferredLongSide: preferredLongSide,
      );
      contentType = 'image/jpeg';
    }

    final bytes = await preparedFile.length();
    if (bytes <= 0 || bytes > _serverLimitBytes) {
      try {
        await preparedFile.delete();
      } on FileSystemException {
        // The invalid file must not prevent a clear validation error.
      }
      throw const FormatException('图片处理后仍超过20MB，请选择更小的图片');
    }
    final preparedBytes = await preparedFile.readAsBytes();
    final dimensions = await _decodeSize(preparedBytes);
    final digest = sha256.convert(preparedBytes).toString();

    return PreparedImage(
      localPath: preparedFile.path,
      fileName: path.basename(preparedFile.path),
      contentType: contentType,
      bytes: bytes,
      sha256: digest,
      width: dimensions.$1,
      height: dimensions.$2,
    );
  }

  Future<Directory> _pendingDirectory() async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory(
      path.join(support.path, 'fangyuanli', 'media', 'pending'),
    );
    await directory.create(recursive: true);
    return directory;
  }

  Future<void> _compress({
    required String sourcePath,
    required String targetPath,
    required int sourceWidth,
    required int sourceHeight,
    required int preferredLongSide,
  }) async {
    final sourceLongSide = sourceWidth > sourceHeight
        ? sourceWidth
        : sourceHeight;
    final scale = sourceLongSide > preferredLongSide
        ? preferredLongSide / sourceLongSide
        : 1.0;
    final targetWidth = (sourceWidth * scale).round();
    final targetHeight = (sourceHeight * scale).round();
    for (final quality in const [86, 76, 68]) {
      final result = await FlutterImageCompress.compressAndGetFile(
        sourcePath,
        targetPath,
        minWidth: targetWidth,
        minHeight: targetHeight,
        quality: quality,
        format: CompressFormat.jpeg,
        keepExif: false,
      );
      if (result == null) {
        throw const FormatException('图片压缩失败，请重新选择');
      }
      if (await result.length() <= _preferredMaxBytes) return;
    }
  }

  Future<(int, int)> _decodeSize(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final size = (frame.image.width, frame.image.height);
    frame.image.dispose();
    codec.dispose();
    return size;
  }

  String? _contentType(String fileName) =>
      switch (path.extension(fileName).toLowerCase()) {
        '.jpg' || '.jpeg' => 'image/jpeg',
        '.png' => 'image/png',
        '.webp' => 'image/webp',
        '.heic' => 'image/heic',
        '.heif' => 'image/heif',
        _ => null,
      };
}
