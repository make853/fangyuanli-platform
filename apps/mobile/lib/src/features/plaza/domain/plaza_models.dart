import 'package:flutter/foundation.dart';

enum PlazaRelation { main, adjacent }

enum UnreadAppearance { none, red, gray }

@immutable
class PlazaUnreadState {
  const PlazaUnreadState({
    this.count = 0,
    this.appearance = UnreadAppearance.none,
    this.firstUnreadSequence,
  });

  factory PlazaUnreadState.fromJson(Map<String, dynamic> json) {
    return PlazaUnreadState(
      count: json['count'] as int? ?? 0,
      appearance: UnreadAppearance.values.firstWhere(
        (value) => value.name == json['appearance'],
        orElse: () => UnreadAppearance.none,
      ),
      firstUnreadSequence: json['firstUnreadSequence'] as int?,
    );
  }

  final int count;
  final UnreadAppearance appearance;
  final int? firstUnreadSequence;

  Map<String, dynamic> toJson() => {
    'count': count,
    'appearance': appearance.name,
    'firstUnreadSequence': firstUnreadSequence,
  };
}

@immutable
class PlazaSummary {
  const PlazaSummary({
    required this.id,
    this.conversationId,
    required this.name,
    required this.isPrimary,
    this.activePeople,
    this.unreadCount = 0,
    this.canView = true,
    this.canSpeak = true,
    this.unreadAppearance = UnreadAppearance.none,
    this.firstUnreadSequence,
  });

  factory PlazaSummary.fromJson(Map<String, dynamic> json) {
    final unread = PlazaUnreadState.fromJson(
      Map<String, dynamic>.from(json['unread'] as Map? ?? const {}),
    );
    return PlazaSummary(
      id: json['plazaId'] as String,
      conversationId: json['conversationId'] as String,
      name: json['name'] as String,
      isPrimary: json['relation'] == PlazaRelation.main.name,
      activePeople: json['activePeople'] as int?,
      canView: json['canView'] as bool? ?? false,
      canSpeak: json['canSpeak'] as bool? ?? false,
      unreadCount: unread.count,
      unreadAppearance: unread.appearance,
      firstUnreadSequence: unread.firstUnreadSequence,
    );
  }

  final String id;
  final String? conversationId;
  final String name;
  final int? activePeople;
  final bool isPrimary;
  final int unreadCount;
  final bool canView;
  final bool canSpeak;
  final UnreadAppearance unreadAppearance;
  final int? firstUnreadSequence;

  PlazaRelation get relation =>
      isPrimary ? PlazaRelation.main : PlazaRelation.adjacent;

  String get activityLabel =>
      activePeople == null ? (canSpeak ? '可发言' : '仅查看') : '$activePeople人活跃';

  PlazaSummary copyWithUnread(PlazaUnreadState unread) {
    return PlazaSummary(
      id: id,
      conversationId: conversationId,
      name: name,
      isPrimary: isPrimary,
      activePeople: activePeople,
      unreadCount: unread.count,
      canView: canView,
      canSpeak: canSpeak,
      unreadAppearance: unread.appearance,
      firstUnreadSequence: unread.firstUnreadSequence,
    );
  }

  Map<String, dynamic> toJson() => {
    'plazaId': id,
    'conversationId': conversationId,
    'name': name,
    'relation': relation.name,
    'canView': canView,
    'canSpeak': canSpeak,
    'activePeople': activePeople,
    'unread': PlazaUnreadState(
      count: unreadCount,
      appearance: unreadAppearance,
      firstUnreadSequence: firstUnreadSequence,
    ).toJson(),
  };
}
