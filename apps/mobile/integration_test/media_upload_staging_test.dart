import 'dart:io';
import 'dart:ui' as ui;

import 'package:fangyuanli_mobile/src/core/config/app_environment.dart';
import 'package:fangyuanli_mobile/src/core/network/api_failure.dart';
import 'package:fangyuanli_mobile/src/core/network/authenticated_api_client.dart';
import 'package:fangyuanli_mobile/src/features/auth/data/auth_api.dart';
import 'package:fangyuanli_mobile/src/features/media/application/media_upload_coordinator.dart';
import 'package:fangyuanli_mobile/src/features/media/data/image_pipeline.dart';
import 'package:fangyuanli_mobile/src/features/media/data/media_upload_api.dart';
import 'package:fangyuanli_mobile/src/features/media/data/media_upload_task_store.dart';
import 'package:fangyuanli_mobile/src/features/media/domain/media_upload_models.dart';
import 'package:fangyuanli_mobile/src/features/profile/data/profile_repository.dart';
import 'package:fangyuanli_mobile/src/features/profile/domain/profile_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

const _apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://127.0.0.1:3000',
);
const _testPhone = String.fromEnvironment('STAGING_TEST_PHONE');
const _testCode = String.fromEnvironment('STAGING_TEST_CODE');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'uploads to staging COS and recovers from interruption and expiry',
    (_) async {
      _requireStagingDefines();
      final environment = AppEnvironment(
        flavor: AppFlavor.staging,
        apiBaseUrl: _apiBaseUrl,
        realtimeUrl: _realtimeUrl(_apiBaseUrl),
      );
      final workingDirectory = Directory(
        '${(await getTemporaryDirectory()).path}/media-upload-acceptance',
      );
      if (await workingDirectory.exists()) {
        await workingDirectory.delete(recursive: true);
      }
      await workingDirectory.create(recursive: true);

      AuthenticatedApiClient? client;
      HttpProfileRepository? profileRepository;
      UserProfile? boundProfile;
      String? originalAvatarMediaId;
      try {
        final prepared = await _prepareImage(workingDirectory, name: 'normal');

        expect(prepared.bytes, greaterThan(0));
        expect(prepared.bytes, lessThanOrEqualTo(6 * 1024 * 1024));
        expect(prepared.width, lessThanOrEqualTo(1600));
        expect(prepared.height, lessThanOrEqualTo(1600));

        final authApi = AuthApi(environment: environment);
        final challenge = await authApi.sendLoginCode(_testPhone);
        final session = await authApi.verifyLoginCode(
          challenge: challenge,
          code: _testCode,
        );
        client = AuthenticatedApiClient(
          environment: environment,
          loadSession: ({bool forceRefresh = false}) async => session,
        );
        final mediaApi = HttpMediaUploadApi(client);
        profileRepository = HttpProfileRepository(client);
        final coordinator = MediaUploadCoordinator(
          session.userId,
          const _UnusedPicker(),
          const _UnusedPreparer(),
          mediaApi,
          DioObjectUploader(),
          FileMediaUploadTaskStore(
            directoryLoader: () async => workingDirectory,
          ),
        );

        final uploaded = await coordinator.enqueuePrepared(
          purpose: MediaPurpose.avatar,
          image: prepared,
        );

        expect(uploaded.status, MediaUploadStatus.processing);
        expect(uploaded.mediaId, isNotNull);
        expect(await File(prepared.localPath).exists(), isFalse);

        final remote = await mediaApi.loadMedia(
          uploaded.mediaId!,
          ownerUserId: session.userId,
        );
        expect(remote.mediaId, uploaded.mediaId);
        expect(remote.status, 'processing');

        final resumableImage = await _prepareImage(
          workingDirectory,
          name: 'resumable',
        );
        final failOnceUploader = _FailOnceUploader(DioObjectUploader());
        final resumableCoordinator = MediaUploadCoordinator(
          session.userId,
          const _UnusedPicker(),
          const _UnusedPreparer(),
          mediaApi,
          failOnceUploader,
          FileMediaUploadTaskStore(
            directoryLoader: () async => workingDirectory,
          ),
        );
        final paused = await resumableCoordinator.enqueuePrepared(
          purpose: MediaPurpose.avatar,
          image: resumableImage,
        );

        expect(paused.status, MediaUploadStatus.paused);
        expect(paused.ticket, isNotNull);
        expect(paused.mediaId, isNull);
        expect(await File(resumableImage.localPath).exists(), isTrue);

        final resumed = await resumableCoordinator.resume(paused);
        expect(resumed.status, MediaUploadStatus.processing);
        expect(resumed.mediaId, isNotNull);
        expect(resumed.ticket?.uploadId, paused.ticket?.uploadId);
        expect(resumed.attempts, 2);
        expect(failOnceUploader.calls, 2);
        expect(await File(resumableImage.localPath).exists(), isFalse);

        final expiredImage = await _prepareImage(
          workingDirectory,
          name: 'expired-ticket',
        );
        final now = DateTime.now().toUtc();
        final expired =
            MediaUploadTask.fromPrepared(
              taskId: 'expired-${now.microsecondsSinceEpoch}',
              ownerUserId: session.userId,
              purpose: MediaPurpose.avatar,
              image: expiredImage,
              createIdempotencyKey:
                  'expired-create-${now.microsecondsSinceEpoch}',
              completeIdempotencyKey:
                  'expired-complete-${now.microsecondsSinceEpoch}',
              now: now,
            ).copyWith(
              ticket: MediaUploadTicket(
                uploadId: 'expired-ticket',
                method: 'PUT',
                uploadUrl: Uri.parse('https://expired.invalid/object'),
                headers: const {'Content-Type': 'image/jpeg'},
                expiresAt: now.subtract(const Duration(minutes: 1)),
              ),
            );
        final renewed = await coordinator.resume(expired);

        expect(renewed.status, MediaUploadStatus.processing);
        expect(renewed.mediaId, isNotNull);
        expect(renewed.ticket?.uploadId, isNot('expired-ticket'));
        expect(await File(expiredImage.localPath).exists(), isFalse);

        final ready = await coordinator.waitUntilReady(
          uploaded,
          timeout: const Duration(minutes: 2),
          pollInterval: const Duration(seconds: 1),
        );
        expect(ready.status, MediaUploadStatus.ready);
        expect(ready.mediaId, isNotNull);

        final beforeBinding = await profileRepository.loadMine();
        originalAvatarMediaId = beforeBinding.avatar?.mediaId;
        boundProfile = await profileRepository.updateMine(
          ownerUserId: session.userId,
          expectedVersion: beforeBinding.profileVersion,
          avatar: ProfileMediaChange.set(ready.mediaId),
        );
        expect(boundProfile.avatar?.mediaId, ready.mediaId);
        expect(boundProfile.avatar?.url, isNotNull);
        expect(boundProfile.avatar?.thumbnailUrl, isNotNull);
        expect(
          await _downloadStatus(boundProfile.avatar!.thumbnailUrl!),
          HttpStatus.ok,
        );
      } finally {
        if (profileRepository != null && boundProfile != null) {
          try {
            await profileRepository.updateMine(
              ownerUserId: boundProfile.userId,
              expectedVersion: boundProfile.profileVersion,
              avatar: originalAvatarMediaId == null
                  ? const ProfileMediaChange.remove()
                  : ProfileMediaChange.set(originalAvatarMediaId),
            );
          } on Object {
            // The acceptance result must retain the original failure; staging
            // cleanup can be retried independently when a concurrent edit wins.
          }
        }
        client?.close();
        if (await workingDirectory.exists()) {
          await workingDirectory.delete(recursive: true);
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

Future<int> _downloadStatus(Uri url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  try {
    final request = await client.getUrl(url);
    final response = await request.close();
    await response.drain<void>();
    return response.statusCode;
  } finally {
    client.close(force: true);
  }
}

Future<PreparedImage> _prepareImage(
  Directory workingDirectory, {
  required String name,
}) async {
  final source = File('${workingDirectory.path}/$name.png');
  await _writeLargePng(source);
  return DefaultMediaImagePreparer().prepare(
    XFile(source.path),
    MediaPurpose.avatar,
  );
}

void _requireStagingDefines() {
  if (_testPhone.trim().isEmpty || _testCode.trim().isEmpty) {
    throw StateError(
      '请通过 --dart-define 提供 STAGING_TEST_PHONE 和 STAGING_TEST_CODE',
    );
  }
  if (_testCode.length != 6 || int.tryParse(_testCode) == null) {
    throw StateError('STAGING_TEST_CODE 必须是6位数字');
  }
}

String _realtimeUrl(String apiBaseUrl) {
  final uri = Uri.parse(apiBaseUrl);
  return uri
      .replace(scheme: uri.scheme == 'https' ? 'wss' : 'ws', path: '/ws/v1')
      .toString();
}

Future<void> _writeLargePng(File target) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const size = Size(2400, 1800);
  canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFE5F2EC));
  canvas.drawCircle(
    const Offset(1200, 900),
    520,
    Paint()..color = const Color(0xFF167A5B),
  );
  final image = await recorder.endRecording().toImage(
    size.width.toInt(),
    size.height.toInt(),
  );
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (bytes == null) throw StateError('无法生成测试图片');
  await target.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
}

class _UnusedPicker implements MediaImagePicker {
  const _UnusedPicker();

  @override
  Future<XFile?> pick(MediaImageSource source) => Future.value();
}

class _UnusedPreparer implements MediaImagePreparer {
  const _UnusedPreparer();

  @override
  Future<PreparedImage> prepare(XFile source, MediaPurpose purpose) {
    throw UnimplementedError();
  }
}

class _FailOnceUploader implements ObjectUploader {
  _FailOnceUploader(this._delegate);

  final ObjectUploader _delegate;
  int calls = 0;

  @override
  Future<String> upload({
    required File file,
    required MediaUploadTicket ticket,
  }) {
    calls += 1;
    if (calls == 1) {
      throw const ApiFailure(message: '模拟上传过程中网络中断');
    }
    return _delegate.upload(file: file, ticket: ticket);
  }
}
