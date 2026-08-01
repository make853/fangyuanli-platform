import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../media/application/media_upload_coordinator.dart';
import '../../media/data/image_pipeline.dart';
import '../../media/domain/media_upload_models.dart';
import '../data/profile_repository.dart';
import '../domain/profile_models.dart';

enum ProfileMediaSlot { avatar, background }

enum ProfileMediaAction { updated, cancelled, failed }

class ProfileState {
  const ProfileState({
    this.profile,
    this.privacy,
    this.isLoading = false,
    this.isSaving = false,
    this.isUpdatingMedia = false,
    this.mediaStatusMessage,
    this.errorMessage,
  });

  final UserProfile? profile;
  final PrivacySettings? privacy;
  final bool isLoading;
  final bool isSaving;
  final bool isUpdatingMedia;
  final String? mediaStatusMessage;
  final String? errorMessage;

  ProfileState copyWith({
    UserProfile? profile,
    PrivacySettings? privacy,
    bool? isLoading,
    bool? isSaving,
    bool? isUpdatingMedia,
    String? mediaStatusMessage,
    bool clearMediaStatus = false,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ProfileState(
      profile: profile ?? this.profile,
      privacy: privacy ?? this.privacy,
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      isUpdatingMedia: isUpdatingMedia ?? this.isUpdatingMedia,
      mediaStatusMessage: clearMediaStatus
          ? null
          : mediaStatusMessage ?? this.mediaStatusMessage,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

class ProfileController extends StateNotifier<ProfileState> {
  ProfileController(this._repository, this._mediaUploads)
    : super(const ProfileState()) {
    unawaited(load());
  }

  final ProfileRepository _repository;
  final MediaUploadCoordinator Function() _mediaUploads;

  Future<void> load({bool silent = false}) async {
    if (!silent) {
      state = state.copyWith(isLoading: true, clearError: true);
    }
    try {
      final results = await Future.wait([
        _repository.loadMine(),
        _repository.loadPrivacy(),
      ]);
      state = state.copyWith(
        profile: results[0] as UserProfile,
        privacy: results[1] as PrivacySettings,
        isLoading: false,
        isSaving: false,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        isSaving: false,
        errorMessage: error.toString(),
      );
    }
  }

  Future<bool> updateProfile({
    required String nickname,
    required ProfileGender gender,
    required String signature,
  }) async {
    final current = state.profile;
    if (current == null || state.isSaving) return false;
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final profile = await _repository.updateMine(
        ownerUserId: current.userId,
        expectedVersion: current.profileVersion,
        nickname: nickname,
        gender: gender,
        signature: signature,
      );
      state = state.copyWith(profile: profile, isSaving: false);
      return true;
    } catch (error) {
      state = state.copyWith(isSaving: false, errorMessage: error.toString());
      return false;
    }
  }

  Future<ProfileMediaAction> pickAndBindMedia({
    required ProfileMediaSlot slot,
    required MediaImageSource source,
  }) async {
    final current = state.profile;
    if (current == null || state.isSaving || state.isUpdatingMedia) {
      return ProfileMediaAction.failed;
    }
    state = state.copyWith(
      isUpdatingMedia: true,
      mediaStatusMessage: '正在选择图片…',
      clearError: true,
    );
    try {
      final uploads = _mediaUploads();
      var task = await uploads.pickAndUpload(
        purpose: slot == ProfileMediaSlot.avatar
            ? MediaPurpose.avatar
            : MediaPurpose.background,
        source: source,
      );
      if (task == null) {
        state = state.copyWith(isUpdatingMedia: false, clearMediaStatus: true);
        return ProfileMediaAction.cancelled;
      }
      state = state.copyWith(mediaStatusMessage: '正在处理图片…');
      task = await uploads.waitUntilReady(task);
      if (task.status != MediaUploadStatus.ready || task.mediaId == null) {
        final message = task.errorMessage ?? '图片尚未处理完成，请稍后重试';
        state = state.copyWith(
          isUpdatingMedia: false,
          mediaStatusMessage: message,
          errorMessage: message,
        );
        return ProfileMediaAction.failed;
      }
      final profile = await _repository.updateMine(
        ownerUserId: current.userId,
        expectedVersion: current.profileVersion,
        avatar: slot == ProfileMediaSlot.avatar
            ? ProfileMediaChange.set(task.mediaId)
            : const ProfileMediaChange.keep(),
        background: slot == ProfileMediaSlot.background
            ? ProfileMediaChange.set(task.mediaId)
            : const ProfileMediaChange.keep(),
      );
      state = state.copyWith(
        profile: profile,
        isUpdatingMedia: false,
        clearMediaStatus: true,
        clearError: true,
      );
      return ProfileMediaAction.updated;
    } catch (error) {
      state = state.copyWith(
        isUpdatingMedia: false,
        mediaStatusMessage: error.toString(),
        errorMessage: error.toString(),
      );
      return ProfileMediaAction.failed;
    }
  }

  Future<bool> removeMedia(ProfileMediaSlot slot) async {
    final current = state.profile;
    if (current == null || state.isSaving || state.isUpdatingMedia) {
      return false;
    }
    state = state.copyWith(
      isUpdatingMedia: true,
      mediaStatusMessage: '正在更新资料…',
      clearError: true,
    );
    try {
      final profile = await _repository.updateMine(
        ownerUserId: current.userId,
        expectedVersion: current.profileVersion,
        avatar: slot == ProfileMediaSlot.avatar
            ? const ProfileMediaChange.remove()
            : const ProfileMediaChange.keep(),
        background: slot == ProfileMediaSlot.background
            ? const ProfileMediaChange.remove()
            : const ProfileMediaChange.keep(),
      );
      state = state.copyWith(
        profile: profile,
        isUpdatingMedia: false,
        clearMediaStatus: true,
        clearError: true,
      );
      return true;
    } catch (error) {
      state = state.copyWith(
        isUpdatingMedia: false,
        mediaStatusMessage: error.toString(),
        errorMessage: error.toString(),
      );
      return false;
    }
  }

  Future<bool> updatePrivacy({
    bool? strangersCanViewProfile,
    bool? searchableByFangyuanNumber,
    bool? globalGroupMuted,
  }) async {
    if (state.isSaving) return false;
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final privacy = await _repository.updatePrivacy(
        strangersCanViewProfile: strangersCanViewProfile,
        searchableByFangyuanNumber: searchableByFangyuanNumber,
        globalGroupMuted: globalGroupMuted,
      );
      state = state.copyWith(privacy: privacy, isSaving: false);
      return true;
    } catch (error) {
      state = state.copyWith(isSaving: false, errorMessage: error.toString());
      return false;
    }
  }
}

final profileControllerProvider =
    StateNotifierProvider<ProfileController, ProfileState>(
      (ref) => ProfileController(
        ref.watch(profileRepositoryProvider),
        () => ref.read(mediaUploadCoordinatorProvider),
      ),
    );
