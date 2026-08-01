import '../../media/domain/media_upload_models.dart';

enum ProfileGender {
  unspecified,
  male,
  female,
  custom,
  hidden;

  static ProfileGender fromJson(String? value) {
    return switch (value) {
      'male' => ProfileGender.male,
      'female' => ProfileGender.female,
      'custom' => ProfileGender.custom,
      'hidden' => ProfileGender.hidden,
      _ => ProfileGender.unspecified,
    };
  }

  String get wireValue => switch (this) {
    ProfileGender.unspecified => 'unspecified',
    ProfileGender.male => 'male',
    ProfileGender.female => 'female',
    ProfileGender.custom => 'custom',
    ProfileGender.hidden => 'hidden',
  };

  String get label => switch (this) {
    ProfileGender.unspecified => '保密',
    ProfileGender.male => '男',
    ProfileGender.female => '女',
    ProfileGender.custom => '自定义',
    ProfileGender.hidden => '未公开',
  };
}

enum ProfileVisibility {
  full,
  limited;

  static ProfileVisibility fromJson(String? value) {
    return value == 'limited'
        ? ProfileVisibility.limited
        : ProfileVisibility.full;
  }
}

enum ProfileRelationshipState {
  self,
  stranger,
  requestPending,
  friend,
  blocked;

  static ProfileRelationshipState fromJson(String? value) {
    return switch (value) {
      'self' => ProfileRelationshipState.self,
      'requestPending' => ProfileRelationshipState.requestPending,
      'friend' => ProfileRelationshipState.friend,
      'blocked' => ProfileRelationshipState.blocked,
      _ => ProfileRelationshipState.stranger,
    };
  }
}

class ProfileRelationship {
  const ProfileRelationship({
    required this.state,
    required this.canStartDirectChat,
    required this.isBlockedByMe,
    required this.hasBlockedMe,
    required this.canViewMyPosts,
  });

  factory ProfileRelationship.fromJson(Map<String, dynamic> json) {
    return ProfileRelationship(
      state: ProfileRelationshipState.fromJson(json['state'] as String?),
      canStartDirectChat: json['canStartDirectChat'] as bool? ?? false,
      isBlockedByMe: json['isBlockedByMe'] as bool? ?? false,
      hasBlockedMe: json['hasBlockedMe'] as bool? ?? false,
      canViewMyPosts: json['canViewMyPosts'] as bool? ?? false,
    );
  }

  final ProfileRelationshipState state;
  final bool canStartDirectChat;
  final bool isBlockedByMe;
  final bool hasBlockedMe;
  final bool canViewMyPosts;
}

class UserProfile {
  const UserProfile({
    required this.userId,
    required this.displayName,
    required this.fangyuanNumber,
    required this.nickname,
    required this.gender,
    required this.signature,
    required this.visibility,
    required this.profileVersion,
    required this.relationship,
    required this.allowedActions,
    this.avatar,
    this.background,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      userId: json['userId'] as String,
      displayName: json['displayName'] as String? ?? '用户',
      fangyuanNumber: json['fangyuanNumber'] as String?,
      nickname: json['nickname'] as String?,
      gender: ProfileGender.fromJson(json['gender'] as String?),
      signature: json['signature'] as String? ?? '',
      visibility: ProfileVisibility.fromJson(
        json['profileVisibility'] as String?,
      ),
      profileVersion: json['profileVersion'] as int? ?? 1,
      relationship: ProfileRelationship.fromJson(
        Map<String, dynamic>.from(json['relationship'] as Map),
      ),
      allowedActions: [
        for (final action in json['allowedActions'] as List? ?? const [])
          action as String,
      ],
      avatar: _optionalMedia(json['avatar']),
      background: _optionalMedia(json['background']),
    );
  }

  final String userId;
  final String displayName;
  final String? fangyuanNumber;
  final String? nickname;
  final ProfileGender gender;
  final String signature;
  final ProfileVisibility visibility;
  final int profileVersion;
  final ProfileRelationship relationship;
  final List<String> allowedActions;
  final MediaAsset? avatar;
  final MediaAsset? background;

  String get initial {
    final value = nickname?.trim() ?? displayName.trim();
    return value.isEmpty ? '方' : String.fromCharCode(value.runes.first);
  }

  static MediaAsset? _optionalMedia(Object? value) => value is Map
      ? MediaAsset.fromJson(Map<String, dynamic>.from(value))
      : null;
}

class ProfileMediaChange {
  const ProfileMediaChange.keep() : isSpecified = false, mediaId = null;

  const ProfileMediaChange.set(this.mediaId) : isSpecified = true;

  const ProfileMediaChange.remove() : isSpecified = true, mediaId = null;

  final bool isSpecified;
  final String? mediaId;
}

class PrivacySettings {
  const PrivacySettings({
    required this.strangersCanViewProfile,
    required this.searchableByFangyuanNumber,
    required this.globalGroupMuted,
    required this.updatedAt,
  });

  factory PrivacySettings.fromJson(Map<String, dynamic> json) {
    return PrivacySettings(
      strangersCanViewProfile: json['strangersCanViewProfile'] as bool? ?? true,
      searchableByFangyuanNumber:
          json['searchableByFangyuanNumber'] as bool? ?? true,
      globalGroupMuted: json['globalGroupMuted'] as bool? ?? false,
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  final bool strangersCanViewProfile;
  final bool searchableByFangyuanNumber;
  final bool globalGroupMuted;
  final DateTime updatedAt;
}
