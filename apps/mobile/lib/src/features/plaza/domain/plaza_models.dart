import 'package:flutter/foundation.dart';

@immutable
class PlazaSummary {
  const PlazaSummary({
    required this.id,
    required this.name,
    required this.activePeople,
    required this.isPrimary,
    this.unreadCount = 0,
  });

  final String id;
  final String name;
  final int activePeople;
  final bool isPrimary;
  final int unreadCount;
}
