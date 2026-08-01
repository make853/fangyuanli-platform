import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_failure.dart';
import '../../../core/network/authenticated_api_client.dart';
import '../../auth/application/auth_controller.dart';
import '../domain/profile_models.dart';

abstract interface class ProfileRepository {
  Future<UserProfile> loadMine();

  Future<UserProfile> loadUser(String userId);

  Future<UserProfile> updateMine({
    required int expectedVersion,
    String? nickname,
    ProfileGender? gender,
    String? signature,
  });

  Future<PrivacySettings> loadPrivacy();

  Future<PrivacySettings> updatePrivacy({
    bool? strangersCanViewProfile,
    bool? searchableByFangyuanNumber,
    bool? globalGroupMuted,
  });
}

class HttpProfileRepository implements ProfileRepository {
  const HttpProfileRepository(this._client);

  final AuthenticatedApiClient _client;

  @override
  Future<UserProfile> loadMine() async {
    final envelope = await _client.get('/me');
    return UserProfile.fromJson(_data(envelope));
  }

  @override
  Future<UserProfile> loadUser(String userId) async {
    final envelope = await _client.get('/users/$userId');
    return UserProfile.fromJson(_data(envelope));
  }

  @override
  Future<UserProfile> updateMine({
    required int expectedVersion,
    String? nickname,
    ProfileGender? gender,
    String? signature,
  }) async {
    final envelope = await _client.patch(
      '/me',
      idempotent: true,
      data: {
        'expectedVersion': expectedVersion,
        'nickname': ?nickname,
        if (gender != null) 'gender': gender.wireValue,
        'signature': ?signature,
      },
    );
    return UserProfile.fromJson(_data(envelope));
  }

  @override
  Future<PrivacySettings> loadPrivacy() async {
    final envelope = await _client.get('/me/privacy');
    return PrivacySettings.fromJson(_data(envelope));
  }

  @override
  Future<PrivacySettings> updatePrivacy({
    bool? strangersCanViewProfile,
    bool? searchableByFangyuanNumber,
    bool? globalGroupMuted,
  }) async {
    final envelope = await _client.patch(
      '/me/privacy',
      idempotent: true,
      data: {
        'strangersCanViewProfile': ?strangersCanViewProfile,
        'searchableByFangyuanNumber': ?searchableByFangyuanNumber,
        'globalGroupMuted': ?globalGroupMuted,
      },
    );
    return PrivacySettings.fromJson(_data(envelope));
  }

  Map<String, dynamic> _data(Map<String, dynamic> envelope) {
    final data = envelope['data'];
    if (data is! Map<String, dynamic>) {
      throw const ApiFailure(message: '服务器返回的数据格式不正确');
    }
    return data;
  }
}

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  final environment = ref.watch(appEnvironmentProvider);
  final authController = ref.read(authControllerProvider.notifier);
  return HttpProfileRepository(
    AuthenticatedApiClient(
      environment: environment,
      loadSession: authController.validSession,
    ),
  );
});

final userProfileProvider = FutureProvider.autoDispose
    .family<UserProfile, String>(
      (ref, userId) => ref.watch(profileRepositoryProvider).loadUser(userId),
    );
