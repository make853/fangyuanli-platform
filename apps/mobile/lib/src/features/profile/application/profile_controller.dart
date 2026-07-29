import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/profile_repository.dart';
import '../domain/profile_models.dart';

class ProfileState {
  const ProfileState({
    this.profile,
    this.privacy,
    this.isLoading = false,
    this.isSaving = false,
    this.errorMessage,
  });

  final UserProfile? profile;
  final PrivacySettings? privacy;
  final bool isLoading;
  final bool isSaving;
  final String? errorMessage;

  ProfileState copyWith({
    UserProfile? profile,
    PrivacySettings? privacy,
    bool? isLoading,
    bool? isSaving,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ProfileState(
      profile: profile ?? this.profile,
      privacy: privacy ?? this.privacy,
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

class ProfileController extends StateNotifier<ProfileState> {
  ProfileController(this._repository) : super(const ProfileState()) {
    unawaited(load());
  }

  final ProfileRepository _repository;

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
    StateNotifierProvider.autoDispose<ProfileController, ProfileState>(
      (ref) => ProfileController(ref.watch(profileRepositoryProvider)),
    );
