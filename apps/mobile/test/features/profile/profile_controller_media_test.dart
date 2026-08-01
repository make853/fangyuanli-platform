import 'package:fangyuanli_mobile/src/features/media/application/media_upload_coordinator.dart';
import 'package:fangyuanli_mobile/src/features/media/data/image_cropper.dart';
import 'package:fangyuanli_mobile/src/features/media/data/image_pipeline.dart';
import 'package:fangyuanli_mobile/src/features/media/domain/media_upload_models.dart';
import 'package:fangyuanli_mobile/src/features/profile/application/profile_controller.dart';
import 'package:fangyuanli_mobile/src/features/profile/data/profile_repository.dart';
import 'package:fangyuanli_mobile/src/features/profile/domain/profile_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  test('avatar is cropped before upload and bound only after ready', () async {
    final repository = _ProfileRepository();
    final uploads = _MediaWorkflow();
    final cropper = _ImageCropper();
    final controller = ProfileController(
      repository,
      () => uploads,
      () => cropper,
    );
    await controller.load();

    final result = await controller.pickAndBindMedia(
      slot: ProfileMediaSlot.avatar,
      source: MediaImageSource.gallery,
    );

    expect(result, ProfileMediaAction.updated);
    expect(cropper.paths, ['/tmp/source.jpg']);
    expect(uploads.uploadedPaths, ['/tmp/cropped.jpg']);
    expect(uploads.purposes, [MediaPurpose.avatar]);
    expect(repository.avatarChanges.single.mediaId, _mediaId);
    expect(controller.state.profile?.avatar?.mediaId, _mediaId);
    controller.dispose();
  });

  test(
    'background skips square crop and crop cancellation uploads nothing',
    () async {
      final repository = _ProfileRepository();
      final uploads = _MediaWorkflow();
      final cropper = _ImageCropper(cancel: true);
      final controller = ProfileController(
        repository,
        () => uploads,
        () => cropper,
      );
      await controller.load();

      final cancelled = await controller.pickAndBindMedia(
        slot: ProfileMediaSlot.avatar,
        source: MediaImageSource.camera,
      );
      expect(cancelled, ProfileMediaAction.cancelled);
      expect(uploads.uploadedPaths, isEmpty);

      final background = await controller.pickAndBindMedia(
        slot: ProfileMediaSlot.background,
        source: MediaImageSource.gallery,
      );
      expect(background, ProfileMediaAction.updated);
      expect(uploads.uploadedPaths, ['/tmp/source.jpg']);
      expect(uploads.purposes, [MediaPurpose.background]);
      expect(cropper.paths, ['/tmp/source.jpg']);
      controller.dispose();
    },
  );
}

const _userId = '019f0000-0000-7000-8000-00000000000a';
const _mediaId = '019f0000-0000-7000-8000-00000000000c';
const _relationship = ProfileRelationship(
  state: ProfileRelationshipState.self,
  canStartDirectChat: false,
  isBlockedByMe: false,
  hasBlockedMe: false,
  canViewMyPosts: false,
);

UserProfile _profile({
  int version = 1,
  MediaAsset? avatar,
  MediaAsset? background,
}) => UserProfile(
  userId: _userId,
  displayName: '小桃子',
  fangyuanNumber: 'FY000000000001',
  nickname: '小桃子',
  gender: ProfileGender.unspecified,
  signature: '',
  visibility: ProfileVisibility.full,
  profileVersion: version,
  relationship: _relationship,
  allowedActions: const ['editProfile'],
  avatar: avatar,
  background: background,
);

class _ProfileRepository implements ProfileRepository {
  UserProfile profile = _profile();
  final List<ProfileMediaChange> avatarChanges = [];

  @override
  Future<UserProfile> loadMine() async => profile;

  @override
  Future<UserProfile> loadUser(String userId) async => profile;

  @override
  Future<PrivacySettings> loadPrivacy() async => PrivacySettings(
    strangersCanViewProfile: true,
    searchableByFangyuanNumber: true,
    globalGroupMuted: false,
    updatedAt: DateTime.utc(2026, 8, 2),
  );

  @override
  Future<UserProfile> updateMine({
    required String ownerUserId,
    required int expectedVersion,
    String? nickname,
    ProfileGender? gender,
    String? signature,
    ProfileMediaChange avatar = const ProfileMediaChange.keep(),
    ProfileMediaChange background = const ProfileMediaChange.keep(),
  }) async {
    avatarChanges.add(avatar);
    profile = _profile(
      version: expectedVersion + 1,
      avatar: avatar.isSpecified
          ? avatar.mediaId == null
                ? null
                : const MediaAsset(mediaId: _mediaId, status: 'ready')
          : profile.avatar,
      background: background.isSpecified
          ? background.mediaId == null
                ? null
                : const MediaAsset(mediaId: _mediaId, status: 'ready')
          : profile.background,
    );
    return profile;
  }

  @override
  Future<PrivacySettings> updatePrivacy({
    bool? strangersCanViewProfile,
    bool? searchableByFangyuanNumber,
    bool? globalGroupMuted,
  }) => loadPrivacy();
}

class _MediaWorkflow implements MediaUploadWorkflow {
  final List<String> uploadedPaths = [];
  final List<MediaPurpose> purposes = [];

  @override
  Future<XFile?> pickImage(MediaImageSource source) async =>
      XFile('/tmp/source.jpg');

  @override
  Future<MediaUploadTask> uploadImage({
    required MediaPurpose purpose,
    required XFile source,
  }) async {
    uploadedPaths.add(source.path);
    purposes.add(purpose);
    return _task(purpose);
  }

  @override
  Future<MediaUploadTask> waitUntilReady(
    MediaUploadTask task, {
    Duration timeout = const Duration(seconds: 45),
    Duration pollInterval = const Duration(milliseconds: 600),
  }) async => task;
}

class _ImageCropper implements MediaImageCropper {
  _ImageCropper({this.cancel = false});

  final bool cancel;
  final List<String> paths = [];

  @override
  Future<XFile?> cropAvatar(XFile source) async {
    paths.add(source.path);
    return cancel ? null : XFile('/tmp/cropped.jpg');
  }
}

MediaUploadTask _task(MediaPurpose purpose) => MediaUploadTask(
  taskId: 'task-1',
  ownerUserId: _userId,
  purpose: purpose,
  localPath: '/tmp/prepared.jpg',
  fileName: 'prepared.jpg',
  contentType: 'image/jpeg',
  bytes: 1024,
  sha256: 'test-sha256',
  width: 512,
  height: 512,
  createIdempotencyKey: 'create-1',
  completeIdempotencyKey: 'complete-1',
  status: MediaUploadStatus.ready,
  createdAt: DateTime.utc(2026, 8, 2),
  updatedAt: DateTime.utc(2026, 8, 2),
  mediaId: _mediaId,
);
