import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_failure.dart';
import '../../../core/network/authenticated_api_client.dart';
import '../../../core/network/authenticated_api_client_provider.dart';
import '../domain/place_models.dart';

abstract interface class PlaceRepository {
  Future<List<PlaceSummary>> discover({
    required String locationContextToken,
    required PlaceCategory category,
    String? expectedUserId,
  });
}

class HttpPlaceRepository implements PlaceRepository {
  const HttpPlaceRepository(this._client);

  final AuthenticatedApiClient _client;

  @override
  Future<List<PlaceSummary>> discover({
    required String locationContextToken,
    required PlaceCategory category,
    String? expectedUserId,
  }) async {
    final token = locationContextToken.trim();
    if (token.isEmpty) {
      throw const ApiFailure(message: '请刷新定位后重试');
    }
    final categoryKey = category.wireKey;
    final historyOnly = category == PlaceCategory.history;
    final response = await _client.post(
      '/places/discover',
      headers: {'x-location-context': token},
      expectedUserId: expectedUserId,
      data: {
        'filters': {
          'distanceMeters': 5000,
          if (categoryKey != null) 'categoryKeys': [categoryKey],
          if (historyOnly) 'historyOnly': true,
        },
        'sort': category == PlaceCategory.nearest ? 'distance' : 'recommended',
        'limit': 25,
      },
    );
    final data = response['data'];
    if (data is! Map || data['items'] is! List) {
      throw const ApiFailure(message: '服务器返回的地点数据格式不正确');
    }
    try {
      return (data['items'] as List)
          .map((item) {
            if (item is! Map) {
              throw const ApiFailure(message: '服务器返回的地点数据格式不正确');
            }
            return PlaceSummary.fromJson(
              Map<String, dynamic>.from(item),
              isInHistory: historyOnly,
            );
          })
          .toList(growable: false);
    } on ApiFailure {
      rethrow;
    } catch (_) {
      throw const ApiFailure(message: '服务器返回的地点数据格式不正确');
    }
  }
}

final placeRepositoryProvider = Provider<PlaceRepository>((ref) {
  return HttpPlaceRepository(ref.watch(authenticatedApiClientProvider));
});
