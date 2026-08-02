import 'package:flutter/foundation.dart';

enum PlaceCategory {
  all('全部地点'),
  food('餐饮与商铺'),
  community('住宅与社区'),
  sports('运动与健身'),
  culture('文化与娱乐'),
  nightlife('酒吧与夜生活'),
  publicService('公共服务'),
  park('景区与公园'),
  history('历史进入'),
  nearest('按距离最近');

  const PlaceCategory(this.label);

  final String label;
}

enum PlaceHeat {
  quiet('冷清'),
  neutral('中性'),
  active('活跃'),
  veryActive('非常活跃'),
  hot('火爆');

  const PlaceHeat(this.label);

  final String label;
}

@immutable
class PlaceSummary {
  const PlaceSummary({
    required this.id,
    required this.name,
    required this.icon,
    required this.category,
    required this.typeLabel,
    required this.distanceMeters,
    required this.heat,
    required this.isVerified,
    required this.isCommercial,
    required this.activePeople,
    this.isManagedByMe = false,
    this.isInHistory = false,
    this.unreadCount = 0,
  });

  final String id;
  final String name;
  final String icon;
  final PlaceCategory category;
  final String typeLabel;
  final int distanceMeters;
  final PlaceHeat heat;
  final bool isVerified;
  final bool isCommercial;
  final int activePeople;
  final bool isManagedByMe;
  final bool isInHistory;
  final int unreadCount;
}
