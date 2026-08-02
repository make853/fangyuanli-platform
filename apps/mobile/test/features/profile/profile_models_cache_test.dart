import 'package:fangyuanli_mobile/src/features/media/domain/media_upload_models.dart';
import 'package:fangyuanli_mobile/src/features/profile/domain/profile_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('profile snapshot round-trips relationship and signed media views', () {
    final profile = UserProfile(
      userId: 'user-b',
      displayName: '小桃子',
      fangyuanNumber: 'FY000000000002',
      nickname: '桃子',
      gender: ProfileGender.female,
      signature: '附近见',
      visibility: ProfileVisibility.full,
      profileVersion: 7,
      relationship: const ProfileRelationship(
        state: ProfileRelationshipState.friend,
        canStartDirectChat: true,
        isBlockedByMe: false,
        hasBlockedMe: false,
        canViewMyPosts: true,
      ),
      allowedActions: const ['startDirectChat'],
      avatar: MediaAsset(
        mediaId: 'avatar-v7',
        status: 'ready',
        mediaType: 'image/jpeg',
        thumbnailUrl: Uri.parse('https://media.test/avatar-thumb'),
        url: Uri.parse('https://media.test/avatar'),
        width: 512,
        height: 512,
        expiresAt: DateTime.utc(2026, 8, 2, 12),
      ),
    );

    final restored = UserProfile.fromJson(profile.toJson());

    expect(restored.userId, profile.userId);
    expect(restored.profileVersion, 7);
    expect(restored.relationship.state, ProfileRelationshipState.friend);
    expect(restored.relationship.canStartDirectChat, isTrue);
    expect(restored.avatar?.mediaId, 'avatar-v7');
    expect(restored.avatar?.thumbnailUrl, profile.avatar?.thumbnailUrl);
    expect(restored.avatar?.expiresAt, profile.avatar?.expiresAt);
  });
}
