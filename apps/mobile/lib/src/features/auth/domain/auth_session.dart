import 'dart:convert';

class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.accessTokenExpiresAt,
    required this.refreshToken,
    required this.refreshTokenExpiresAt,
    required this.deviceId,
    required this.userId,
    required this.isNewUser,
  });

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      accessToken: json['accessToken'] as String,
      accessTokenExpiresAt: DateTime.parse(
        json['accessTokenExpiresAt'] as String,
      ).toUtc(),
      refreshToken: json['refreshToken'] as String,
      refreshTokenExpiresAt: DateTime.parse(
        json['refreshTokenExpiresAt'] as String,
      ).toUtc(),
      deviceId: json['deviceId'] as String,
      userId: json['userId'] as String,
      isNewUser: json['isNewUser'] as bool? ?? false,
    );
  }

  factory AuthSession.decode(String value) {
    return AuthSession.fromJson(jsonDecode(value) as Map<String, dynamic>);
  }

  final String accessToken;
  final DateTime accessTokenExpiresAt;
  final String refreshToken;
  final DateTime refreshTokenExpiresAt;
  final String deviceId;
  final String userId;
  final bool isNewUser;

  bool accessTokenNeedsRefresh(DateTime now) {
    return accessTokenExpiresAt.isBefore(
      now.toUtc().add(const Duration(minutes: 1)),
    );
  }

  bool refreshTokenExpired(DateTime now) {
    return !refreshTokenExpiresAt.isAfter(now.toUtc());
  }

  Map<String, dynamic> toJson() => {
    'accessToken': accessToken,
    'accessTokenExpiresAt': accessTokenExpiresAt.toIso8601String(),
    'refreshToken': refreshToken,
    'refreshTokenExpiresAt': refreshTokenExpiresAt.toIso8601String(),
    'deviceId': deviceId,
    'userId': userId,
    'isNewUser': isNewUser,
  };

  String encode() => jsonEncode(toJson());
}
