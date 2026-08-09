import 'dart:async';

import 'package:fangyuanli_mobile/src/features/activities/presentation/activities_screen.dart';
import 'package:fangyuanli_mobile/src/features/places/presentation/places_screen.dart';
import 'package:fangyuanli_mobile/src/features/plaza/data/device_location_source.dart';
import 'package:fangyuanli_mobile/src/features/plaza/data/geo_context_repository.dart';
import 'package:fangyuanli_mobile/src/features/plaza/domain/geo_context_models.dart';
import 'package:fangyuanli_mobile/src/features/plaza/domain/plaza_models.dart';
import 'package:fangyuanli_mobile/src/features/plaza/presentation/plaza_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('真实四广场到达后替换冷启动预览且不展示测试消息', (tester) async {
    final location = _CompletingLocationSource();
    final repository = _FixedGeoContextRepository(
      GeoContext(
        locationContextToken: 'live-location-context',
        expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
        anchor: const GeoAnchorState(
          radiusMeters: 150,
          isReused: true,
          recalculationPending: false,
        ),
        plazas: List.generate(
          4,
          (index) => PlazaSummary(
            id: 'live-$index',
            conversationId: 'conversation-$index',
            name: index == 0 ? '真实主广场' : '真实相邻广场$index',
            isPrimary: index == 0,
          ),
        ),
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceLocationSourceProvider.overrideWithValue(location),
          geoContextRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: Scaffold(body: PlazaScreen())),
      ),
    );

    expect(find.textContaining('当前为交互预览'), findsOneWidget);
    location.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const ValueKey('plaza-chat-live-0')), findsOneWidget);
    expect(find.textContaining('当前为交互预览'), findsNothing);
    expect(find.text('楼下新开的咖啡店今天试营业，有人去过吗？'), findsNothing);
    expect(find.text('已离开此广场，仅可查看历史消息'), findsNothing);
  });

  testWidgets('广场四频道同屏，切换后展示对应频道且未读消失', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceLocationSourceProvider.overrideWithValue(
            _UnavailableLocationSource(),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: PlazaScreen())),
      ),
    );

    expect(find.byKey(const ValueKey('plaza-switch-primary')), findsOneWidget);
    expect(find.byKey(const ValueKey('plaza-switch-east')), findsOneWidget);
    expect(find.byKey(const ValueKey('plaza-switch-river')), findsOneWidget);
    expect(find.byKey(const ValueKey('plaza-switch-culture')), findsOneWidget);
    final screenWidth =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    for (final id in ['primary', 'east', 'river', 'culture']) {
      final rect = tester.getRect(find.byKey(ValueKey('plaza-switch-$id')));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(screenWidth));
    }
    expect(find.text('12'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('plaza-switch-east')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('plaza-chat-east')), findsOneWidget);
    expect(find.text('这个广场暂时还没有消息'), findsOneWidget);
    expect(find.text('12'), findsNothing);
  });

  testWidgets('广场聊天头部紧凑且每张卡片独立进入广场信息', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceLocationSourceProvider.overrideWithValue(
            _UnavailableLocationSource(),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: PlazaScreen())),
      ),
    );

    expect(
      tester.getSize(find.byKey(const ValueKey('plaza-switcher'))).height,
      76,
    );
    expect(find.text('当前位置可进入的4个广场 · 均可发言'), findsNothing);
    expect(find.text('通知设置'), findsNothing);
    expect(find.text('可发言'), findsNothing);
    for (final id in ['primary', 'east', 'river', 'culture']) {
      expect(find.byKey(ValueKey('plaza-more-$id')), findsOneWidget);
    }

    await tester.tap(find.byKey(const ValueKey('plaza-more-east')));
    await tester.pumpAndSettle();
    expect(find.text('广场信息'), findsOneWidget);
    expect(find.text('东街广场'), findsOneWidget);
  });

  testWidgets('区域切换后保留当前旧广场为只读，选择新广场后恢复输入', (tester) async {
    const originalPlazas = [
      PlazaSummary(id: 'old-main', name: '旧主广场', isPrimary: true),
      PlazaSummary(id: 'old-east', name: '旧东广场', isPrimary: false),
      PlazaSummary(id: 'old-west', name: '旧西广场', isPrimary: false),
      PlazaSummary(id: 'old-south', name: '旧南广场', isPrimary: false),
    ];
    const newPlazas = [
      PlazaSummary(id: 'new-main', name: '新主广场', isPrimary: true),
      PlazaSummary(id: 'new-east', name: '新东广场', isPrimary: false),
      PlazaSummary(id: 'new-west', name: '新西广场', isPrimary: false),
      PlazaSummary(id: 'new-south', name: '新南广场', isPrimary: false),
    ];

    Widget app(List<PlazaSummary> plazas) => ProviderScope(
      overrides: [
        deviceLocationSourceProvider.overrideWithValue(
          _UnavailableLocationSource(),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: PlazaScreen(
            key: const ValueKey('plaza-screen'),
            plazas: plazas,
          ),
        ),
      ),
    );

    await tester.pumpWidget(app(originalPlazas));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);

    await tester.pumpWidget(app(newPlazas));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('plaza-chat-old-main')), findsOneWidget);
    expect(find.text('已离开此广场，仅可查看历史消息'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('chat-read-only-surface')),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.byKey(const ValueKey('plaza-switch-new-main')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('plaza-chat-new-main')), findsOneWidget);
    expect(find.text('已离开此广场，仅可查看历史消息'), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('地点卡片主体进入聊天，聊天右上角进入地点详情', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PlacesScreen())),
    );

    await tester.tap(find.byKey(const ValueKey('place-card-jiang')));
    await tester.pumpAndSettle();
    expect(find.text('地点群 · 约300米'), findsOneWidget);

    await tester.tap(find.byTooltip('地点详情'));
    await tester.pumpAndSettle();
    expect(find.text('地点群信息'), findsOneWidget);
    expect(find.text('当前身份：群主'), findsOneWidget);
  });

  testWidgets('活动详情按钮进详情，卡片其他区域进聊天', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ActivitiesScreen())),
    );

    await tester.tap(find.byKey(const ValueKey('activity-details-badminton')));
    await tester.pumpAndSettle();
    expect(find.text('活动介绍'), findsOneWidget);
    expect(find.text('进入活动群'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('activity-card-badminton')));
    await tester.pumpAndSettle();
    expect(find.text('活动群 · 8/10人'), findsOneWidget);
    expect(find.byTooltip('活动详情'), findsOneWidget);
  });

  testWidgets('地点筛选使用项目样式选择面板并筛出运动地点', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PlacesScreen())),
    );

    await tester.tap(find.byKey(const ValueKey('place-category-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('运动与健身').last);
    await tester.pumpAndSettle();

    expect(find.text('云动健身房'), findsOneWidget);
    expect(find.text('滨河健身广场'), findsOneWidget);
    expect(find.text('隆江猪脚饭'), findsNothing);
  });
}

class _UnavailableLocationSource implements DeviceLocationSource {
  const _UnavailableLocationSource();

  @override
  Future<DevicePosition> currentPosition() {
    throw const DeviceLocationUnavailable('测试环境没有定位');
  }
}

class _CompletingLocationSource implements DeviceLocationSource {
  final _completer = Completer<DevicePosition>();

  void complete() {
    _completer.complete(
      DevicePosition(
        coordinateSystem: GeoCoordinateSystem.gcj02,
        longitude: 116.397,
        latitude: 39.908,
        accuracyMeters: 12,
        capturedAt: DateTime.now().toUtc(),
      ),
    );
  }

  @override
  Future<DevicePosition> currentPosition() => _completer.future;
}

class _FixedGeoContextRepository implements GeoContextRepository {
  const _FixedGeoContextRepository(this.context);

  final GeoContext context;

  @override
  Future<GeoContext> refresh(
    DevicePosition position, {
    String? expectedUserId,
  }) async => context;
}
