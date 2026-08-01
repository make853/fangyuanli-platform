import 'package:fangyuanli_mobile/src/features/profile/domain/profile_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses signed avatar and background media without storage keys', () {
    final profile = UserProfile.fromJson({
      'userId': '019f0000-0000-7000-8000-00000000000a',
      'displayName': '小桃子',
      'fangyuanNumber': 'FY000000000001',
      'nickname': '小桃子',
      'gender': 'female',
      'signature': '附近见',
      'profileVisibility': 'full',
      'profileVersion': 2,
      'relationship': {
        'state': 'self',
        'canStartDirectChat': false,
        'isBlockedByMe': false,
        'hasBlockedMe': false,
        'canViewMyPosts': false,
      },
      'allowedActions': ['editProfile'],
      'avatar': {
        'mediaId': 'avatar-media',
        'mediaType': 'image',
        'status': 'ready',
        'url': 'https://media.example/avatar.webp?signature=short-lived',
        'thumbnailUrl':
            'https://media.example/avatar-thumb.webp?signature=short-lived',
        'width': 512,
        'height': 512,
        'expiresAt': '2026-08-02T01:10:00.000Z',
      },
      'background': {
        'mediaId': 'background-media',
        'status': 'ready',
        'url': 'https://media.example/background.webp?signature=short-lived',
        'width': 1440,
        'height': 900,
      },
    });

    expect(profile.avatar?.mediaId, 'avatar-media');
    expect(profile.avatar?.thumbnailUrl?.host, 'media.example');
    expect(profile.avatar?.expiresAt, DateTime.utc(2026, 8, 2, 1, 10));
    expect(profile.background?.mediaId, 'background-media');
    expect(profile.background?.width, 1440);
  });

  test('keeps avatar but withholds background from a limited profile', () {
    final profile = UserProfile.fromJson({
      'userId': '019f0000-0000-7000-8000-00000000000b',
      'displayName': '用户',
      'fangyuanNumber': null,
      'nickname': null,
      'gender': 'hidden',
      'signature': '你好',
      'profileVisibility': 'limited',
      'profileVersion': 1,
      'relationship': {
        'state': 'stranger',
        'canStartDirectChat': false,
        'isBlockedByMe': false,
        'hasBlockedMe': false,
        'canViewMyPosts': false,
      },
      'allowedActions': ['sendFriendRequest'],
      'avatar': {
        'mediaId': 'public-avatar',
        'status': 'ready',
        'url': 'https://media.example/avatar.webp',
      },
      'background': null,
    });

    expect(profile.visibility, ProfileVisibility.limited);
    expect(profile.avatar?.mediaId, 'public-avatar');
    expect(profile.background, isNull);
  });
}
