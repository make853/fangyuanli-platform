import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../domain/geo_context_models.dart';
import 'gcj02_coordinate_converter.dart';

abstract interface class DeviceLocationSource {
  Future<DevicePosition> currentPosition();
}

class DeviceLocationUnavailable implements Exception {
  const DeviceLocationUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
}

class GeolocatorDeviceLocationSource implements DeviceLocationSource {
  const GeolocatorDeviceLocationSource(this._converter);

  final Gcj02CoordinateConverter _converter;

  @override
  Future<DevicePosition> currentPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const DeviceLocationUnavailable('请先打开手机定位服务');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const DeviceLocationUnavailable('需要定位权限才能发现附近广场');
    }
    if (permission == LocationPermission.deniedForever) {
      throw const DeviceLocationUnavailable('请在系统设置中允许方圆里使用定位');
    }

    final raw = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 12),
      ),
    );
    final gcj02 = _converter.fromWgs84(
      longitude: raw.longitude,
      latitude: raw.latitude,
    );
    return DevicePosition(
      coordinateSystem: GeoCoordinateSystem.gcj02,
      longitude: gcj02.longitude,
      latitude: gcj02.latitude,
      accuracyMeters: raw.accuracy,
      capturedAt: raw.timestamp,
    );
  }
}

/// CoreLocation remains a raw sensor boundary. Mainland map, POI and navigation
/// stay on AMap; conversion is isolated here so it can be replaced by the AMap
/// native location SDK without touching plaza controllers or presentation.
final deviceLocationSourceProvider = Provider<DeviceLocationSource>((ref) {
  return GeolocatorDeviceLocationSource(
    ref.watch(gcj02CoordinateConverterProvider),
  );
});
