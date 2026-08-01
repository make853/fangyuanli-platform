import 'package:fangyuanli_mobile/src/features/activities/presentation/activities_screen.dart';
import 'package:fangyuanli_mobile/src/features/places/presentation/places_screen.dart';
import 'package:fangyuanli_mobile/src/features/plaza/presentation/plaza_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('广场四频道同屏，切换后展示对应频道且未读消失', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PlazaScreen())),
    );

    expect(find.byKey(const ValueKey('plaza-switch-primary')), findsOneWidget);
    expect(find.byKey(const ValueKey('plaza-switch-east')), findsOneWidget);
    expect(find.text('12'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('plaza-switch-east')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('plaza-chat-east')), findsOneWidget);
    expect(find.text('这个广场暂时还没有消息'), findsOneWidget);
    expect(find.text('12'), findsNothing);
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
