import 'package:flutter/foundation.dart';

enum ActivityListView {
  nearby('附近'),
  interests('我的爱好'),
  joined('已参加'),
  ended('已结束');

  const ActivityListView(this.label);

  final String label;
}

@immutable
class ActivitySummary {
  const ActivitySummary({
    required this.id,
    required this.name,
    required this.statusLabel,
    required this.timeLabel,
    required this.locationName,
    required this.distanceMeters,
    required this.memberLabel,
    required this.introduction,
    required this.joinRule,
    required this.chatRule,
    required this.creatorName,
    required this.views,
    this.unreadCount = 0,
    this.announcement,
  });

  final String id;
  final String name;
  final String statusLabel;
  final String timeLabel;
  final String locationName;
  final int distanceMeters;
  final String memberLabel;
  final String introduction;
  final String joinRule;
  final String chatRule;
  final String creatorName;
  final Set<ActivityListView> views;
  final int unreadCount;
  final String? announcement;
}
