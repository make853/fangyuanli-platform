import 'package:fangyuanli_mobile/src/features/places/application/place_controller.dart';
import 'package:fangyuanli_mobile/src/features/places/data/place_repository.dart';
import 'package:fangyuanli_mobile/src/features/places/domain/place_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('取得位置令牌后加载真实地点并按服务端类别刷新', () async {
    final repository = _FakePlaceRepository();
    final controller = PlaceController(repository, expectedUserId: 'user-a');

    controller.updateLocationContext('location-a');
    await _waitFor(() => controller.state.items.isNotEmpty);

    expect(repository.tokens, ['location-a']);
    expect(repository.expectedUserIds, ['user-a']);
    expect(controller.state.items.single.name, '地点-all');

    await controller.selectCategory(PlaceCategory.sports);
    expect(repository.categories.last, PlaceCategory.sports);
    expect(controller.state.items.single.name, '地点-sports');
    controller.dispose();
  });

  test('同一个位置令牌不会重复触发地点发现', () async {
    final repository = _FakePlaceRepository();
    final controller = PlaceController(repository);

    controller.updateLocationContext('same-token');
    await _waitFor(() => repository.tokens.isNotEmpty);
    controller.updateLocationContext('same-token');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(repository.tokens, ['same-token']);
    controller.dispose();
  });

  test('导航未读只累计红色提醒', () {
    final state = PlaceState(
      items: [
        _place('red', 3, PlaceUnreadAppearance.red),
        _place('gray', 5, PlaceUnreadAppearance.gray),
        _place('none', 7, PlaceUnreadAppearance.none),
      ],
    );

    expect(state.navigationUnread, 3);
  });
}

PlaceSummary _place(
  String id,
  int unreadCount,
  PlaceUnreadAppearance unreadAppearance,
) {
  return PlaceSummary(
    id: id,
    name: id,
    icon: '📍',
    category: PlaceCategory.transport,
    typeLabel: '交通与其他',
    distanceMeters: 100,
    heat: PlaceHeat.quiet,
    isVerified: false,
    isCommercial: false,
    unreadCount: unreadCount,
    unreadAppearance: unreadAppearance,
  );
}

class _FakePlaceRepository implements PlaceRepository {
  final tokens = <String>[];
  final categories = <PlaceCategory>[];
  final expectedUserIds = <String?>[];

  @override
  Future<List<PlaceSummary>> discover({
    required String locationContextToken,
    required PlaceCategory category,
    String? expectedUserId,
  }) async {
    tokens.add(locationContextToken);
    categories.add(category);
    expectedUserIds.add(expectedUserId);
    return [
      PlaceSummary(
        id: 'place-${category.name}',
        conversationId: 'conversation-${category.name}',
        name: '地点-${category.name}',
        icon: category.icon,
        category: category,
        typeLabel: category.label,
        distanceMeters: 300,
        heat: PlaceHeat.quiet,
        isVerified: false,
        isCommercial: category.isUsuallyCommercial,
      ),
    ];
  }
}

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 50; attempt += 1) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('等待条件超时');
}
