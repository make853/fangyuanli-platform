import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fangyuanli_mobile/src/core/config/app_environment.dart';
import 'package:fangyuanli_mobile/src/core/network/authenticated_api_client.dart';
import 'package:fangyuanli_mobile/src/features/auth/domain/auth_session.dart';
import 'package:fangyuanli_mobile/src/features/places/data/place_repository.dart';
import 'package:fangyuanli_mobile/src/features/places/domain/place_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('地点发现携带短期位置令牌和服务端筛选条件', () async {
    final adapter = _PlaceAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test'))
      ..httpClientAdapter = adapter;
    final client = AuthenticatedApiClient(
      environment: const AppEnvironment(
        flavor: AppFlavor.staging,
        apiBaseUrl: 'https://api.example.test',
        realtimeUrl: 'wss://api.example.test/ws/v1',
      ),
      loadSession: ({bool forceRefresh = false}) async => _session,
      dio: dio,
    );
    addTearDown(client.close);

    final places = await HttpPlaceRepository(client).discover(
      locationContextToken: 'opaque-location-context',
      category: PlaceCategory.food,
      expectedUserId: 'user-1',
    );

    expect(adapter.options.path, '/places/discover');
    expect(
      adapter.options.headers['x-location-context'],
      'opaque-location-context',
    );
    expect(adapter.options.data, {
      'filters': {
        'distanceMeters': 5000,
        'categoryKeys': ['food_retail'],
      },
      'sort': 'recommended',
      'limit': 25,
    });
    expect(places.single.name, '真实餐厅');
    expect(places.single.conversationId, 'conversation-1');
  });
}

final _session = AuthSession(
  accessToken: 'access-token',
  accessTokenExpiresAt: DateTime.utc(2026, 8, 9, 12),
  refreshToken: 'refresh-token',
  refreshTokenExpiresAt: DateTime.utc(2026, 8, 10, 12),
  deviceId: 'device-1',
  userId: 'user-1',
  isNewUser: false,
);

class _PlaceAdapter implements HttpClientAdapter {
  late RequestOptions options;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    this.options = options;
    return ResponseBody.fromString(
      jsonEncode({
        'data': {
          'items': [
            {
              'placeGroupId': 'place-1',
              'conversationId': 'conversation-1',
              'name': '真实餐厅',
              'category': {'key': 'food_retail', 'name': '餐饮与商铺'},
              'distance': {'meters': 300, 'display': '约300米'},
              'certificationStatus': 'unverified',
              'heat': {'level': 'quiet', 'display': '冷清'},
              'unread': {
                'count': 0,
                'appearance': 'none',
                'firstUnreadSequence': null,
              },
              'allowedActions': ['viewDetail', 'enterConversation'],
              'version': 1,
            },
          ],
          'nextCursor': null,
          'hasMore': false,
        },
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
