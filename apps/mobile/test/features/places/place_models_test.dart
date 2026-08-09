import 'package:fangyuanli_mobile/src/features/places/domain/place_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('解析真实地点卡片且不依赖预览活跃人数', () {
    final place = PlaceSummary.fromJson({
      'placeGroupId': 'place-1',
      'conversationId': 'conversation-1',
      'name': '隆江猪脚饭',
      'category': {'key': 'food_retail', 'name': '餐饮与商铺'},
      'distance': {'meters': 315, 'display': '约300米'},
      'certificationStatus': 'verified',
      'heat': {'level': 'veryActive', 'display': '非常活跃'},
      'unread': {'count': 7, 'appearance': 'red', 'firstUnreadSequence': 10},
      'allowedActions': ['viewDetail', 'enterConversation', 'managePlace'],
      'version': 1,
    });

    expect(place.id, 'place-1');
    expect(place.conversationId, 'conversation-1');
    expect(place.category, PlaceCategory.food);
    expect(place.heat, PlaceHeat.veryActive);
    expect(place.isVerified, isTrue);
    expect(place.isManagedByMe, isTrue);
    expect(place.unreadCount, 7);
    expect(place.unreadAppearance, PlaceUnreadAppearance.red);
    expect(place.activePeople, isNull);
  });

  test('未知服务端类别安全落入交通与其他', () {
    expect(PlaceCategory.fromWire('future_category'), PlaceCategory.transport);
  });
}
