import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/authenticated_api_client.dart';
import '../../../core/network/authenticated_api_client_provider.dart';
import 'device_location_source.dart';
import '../domain/geo_context_models.dart';

abstract interface class GeoContextRepository {
  Future<GeoContext> refresh(DevicePosition position, {String? expectedUserId});
}

class ApiGeoContextRepository implements GeoContextRepository {
  const ApiGeoContextRepository(this._client);

  final AuthenticatedApiClient _client;

  @override
  Future<GeoContext> refresh(
    DevicePosition position, {
    String? expectedUserId,
  }) async {
    if (position.coordinateSystem != GeoCoordinateSystem.gcj02) {
      throw const DeviceLocationUnavailable('当前位置不是高德 GCJ-02 坐标，已阻止错误广场计算');
    }
    final response = await _client.post(
      '/geo/context',
      data: position.toRequestJson(),
      idempotent: true,
      expectedUserId: expectedUserId,
    );
    return GeoContext.fromJson(
      Map<String, dynamic>.from(response['data'] as Map),
    );
  }
}

final geoContextRepositoryProvider = Provider<GeoContextRepository>((ref) {
  return ApiGeoContextRepository(ref.watch(authenticatedApiClientProvider));
});
