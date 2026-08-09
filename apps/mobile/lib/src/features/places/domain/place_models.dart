import 'package:flutter/foundation.dart';

enum PlaceCategory {
  all('全部地点'),
  food('餐饮与商铺', wireKey: 'food_retail'),
  community('住宅与社区', wireKey: 'community'),
  sports('运动与健身', wireKey: 'sports_fitness'),
  culture('文化与娱乐', wireKey: 'culture_entertainment'),
  nightlife('酒吧与夜生活', wireKey: 'nightlife'),
  publicService('公共服务', wireKey: 'education_public'),
  park('景区与公园', wireKey: 'parks_scenic'),
  shopping('购物与商圈', wireKey: 'shopping_district'),
  transport('交通与其他', wireKey: 'transport_other'),
  history('历史进入'),
  nearest('按距离最近');

  const PlaceCategory(this.label, {this.wireKey});

  final String label;
  final String? wireKey;

  static PlaceCategory fromWire(String value) {
    return PlaceCategory.values.firstWhere(
      (category) => category.wireKey == value,
      orElse: () => PlaceCategory.transport,
    );
  }
}

enum PlaceHeat {
  quiet('冷清'),
  neutral('中性'),
  active('活跃'),
  veryActive('非常活跃'),
  hot('火爆');

  const PlaceHeat(this.label);

  final String label;

  static PlaceHeat fromWire(String value) => switch (value) {
    'quiet' => PlaceHeat.quiet,
    'neutral' => PlaceHeat.neutral,
    'active' => PlaceHeat.active,
    'veryActive' => PlaceHeat.veryActive,
    'hot' => PlaceHeat.hot,
    _ => PlaceHeat.quiet,
  };
}

enum PlaceUnreadAppearance {
  none,
  red,
  gray;

  static PlaceUnreadAppearance fromWire(String value) => switch (value) {
    'red' => PlaceUnreadAppearance.red,
    'gray' => PlaceUnreadAppearance.gray,
    _ => PlaceUnreadAppearance.none,
  };
}

@immutable
class PlaceImage {
  const PlaceImage({required this.source, required this.url, this.title});

  static PlaceImage? tryParse(Object? value) {
    if (value is! Map) return null;
    final json = Map<String, dynamic>.from(value);
    final source = json['source'];
    final rawUrl = json['url'];
    if (source != 'amap' || rawUrl is! String) return null;
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
    final rawTitle = json['title'];
    return PlaceImage(
      source: source as String,
      url: rawUrl,
      title: rawTitle is String && rawTitle.trim().isNotEmpty
          ? rawTitle.trim()
          : null,
    );
  }

  final String source;
  final String url;
  final String? title;
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
    this.image,
    this.conversationId = '',
    this.activePeople,
    this.isManagedByMe = false,
    this.isInHistory = false,
    this.unreadCount = 0,
    this.unreadAppearance = PlaceUnreadAppearance.none,
  });

  factory PlaceSummary.fromJson(
    Map<String, dynamic> json, {
    bool isInHistory = false,
  }) {
    final categoryJson = Map<String, dynamic>.from(json['category'] as Map);
    final distanceJson = Map<String, dynamic>.from(json['distance'] as Map);
    final heatJson = Map<String, dynamic>.from(json['heat'] as Map);
    final unreadJson = Map<String, dynamic>.from(json['unread'] as Map);
    final category = PlaceCategory.fromWire(categoryJson['key'] as String);
    final allowedActions = (json['allowedActions'] as List)
        .whereType<String>()
        .toSet();
    return PlaceSummary(
      id: json['placeGroupId'] as String,
      conversationId: json['conversationId'] as String,
      name: json['name'] as String,
      icon: category.icon,
      category: category,
      typeLabel: categoryJson['name'] as String,
      distanceMeters: (distanceJson['meters'] as num).round(),
      heat: PlaceHeat.fromWire(heatJson['level'] as String),
      isVerified: json['certificationStatus'] == 'verified',
      isCommercial: category.isUsuallyCommercial,
      image: PlaceImage.tryParse(json['image']),
      isManagedByMe: allowedActions.contains('managePlace'),
      isInHistory: isInHistory,
      unreadCount: (unreadJson['count'] as num).toInt(),
      unreadAppearance: PlaceUnreadAppearance.fromWire(
        unreadJson['appearance'] as String,
      ),
    );
  }

  final String id;
  final String conversationId;
  final String name;
  final String icon;
  final PlaceCategory category;
  final String typeLabel;
  final int distanceMeters;
  final PlaceHeat heat;
  final bool isVerified;
  final bool isCommercial;
  final PlaceImage? image;
  final int? activePeople;
  final bool isManagedByMe;
  final bool isInHistory;
  final int unreadCount;
  final PlaceUnreadAppearance unreadAppearance;
}

extension PlaceCategoryPresentation on PlaceCategory {
  String get icon => switch (this) {
    PlaceCategory.food => '🍚',
    PlaceCategory.community => '🏘️',
    PlaceCategory.sports => '🏋️',
    PlaceCategory.culture => '🎬',
    PlaceCategory.nightlife => '🍸',
    PlaceCategory.publicService => '🏢',
    PlaceCategory.park => '🌳',
    PlaceCategory.shopping => '🛍️',
    PlaceCategory.transport => '🚉',
    PlaceCategory.all || PlaceCategory.history || PlaceCategory.nearest => '📍',
  };

  bool get isUsuallyCommercial => switch (this) {
    PlaceCategory.food ||
    PlaceCategory.culture ||
    PlaceCategory.nightlife ||
    PlaceCategory.shopping => true,
    _ => false,
  };
}
