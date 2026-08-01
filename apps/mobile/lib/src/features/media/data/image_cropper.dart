import 'dart:ui';

import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract interface class MediaImageCropper {
  Future<XFile?> cropAvatar(XFile source);
}

class SystemMediaImageCropper implements MediaImageCropper {
  SystemMediaImageCropper({ImageCropper? cropper})
    : _cropper = cropper ?? ImageCropper();

  final ImageCropper _cropper;

  @override
  Future<XFile?> cropAvatar(XFile source) async {
    final cropped = await _cropper.cropImage(
      sourcePath: source.path,
      maxWidth: 1600,
      maxHeight: 1600,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 92,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: '裁剪头像',
          toolbarColor: const Color(0xFFFFFFFF),
          toolbarWidgetColor: const Color(0xFF26332D),
          activeControlsWidgetColor: const Color(0xFF167A5B),
          lockAspectRatio: true,
          hideBottomControls: false,
          initAspectRatio: CropAspectRatioPreset.square,
          aspectRatioPresets: const [CropAspectRatioPreset.square],
        ),
        IOSUiSettings(
          title: '裁剪头像',
          doneButtonTitle: '完成',
          cancelButtonTitle: '取消',
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
          aspectRatioPickerButtonHidden: true,
          showCancelConfirmationDialog: true,
          aspectRatioPresets: const [CropAspectRatioPreset.square],
        ),
      ],
    );
    return cropped == null ? null : XFile(cropped.path);
  }
}

final mediaImageCropperProvider = Provider<MediaImageCropper>(
  (_) => SystemMediaImageCropper(),
);
