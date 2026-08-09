import 'package:cached_network_image/cached_network_image.dart';
import 'package:fangyuanli_mobile/src/features/places/domain/place_models.dart';
import 'package:fangyuanli_mobile/src/features/places/presentation/place_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('地点有可信图片时使用缓存图片组件', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaceCard(
            place: _place(
              image: const PlaceImage(
                source: 'amap',
                url: 'https://images.example.test/store.jpg',
                title: '门店环境',
              ),
            ),
            onTap: () {},
          ),
        ),
      ),
    );

    expect(find.byType(CachedNetworkImage), findsOneWidget);
    expect(
      find.byKey(const ValueKey('place-thumbnail-place-1')),
      findsOneWidget,
    );
  });

  testWidgets('地点没有图片时稳定回退类别图标', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaceCard(place: _place(), onTap: () {}),
        ),
      ),
    );

    expect(find.byType(CachedNetworkImage), findsNothing);
    expect(
      find.byKey(const ValueKey('place-thumbnail-fallback-place-1')),
      findsOneWidget,
    );
    expect(find.text('🍚'), findsOneWidget);
  });
}

PlaceSummary _place({PlaceImage? image}) {
  return PlaceSummary(
    id: 'place-1',
    conversationId: 'conversation-1',
    name: '隆江猪脚饭',
    icon: '🍚',
    category: PlaceCategory.food,
    typeLabel: '餐饮与商铺',
    distanceMeters: 300,
    heat: PlaceHeat.active,
    isVerified: false,
    isCommercial: true,
    image: image,
  );
}
