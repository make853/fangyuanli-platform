import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

class Gcj02Coordinate {
  const Gcj02Coordinate({required this.longitude, required this.latitude});

  final double longitude;
  final double latitude;
}

abstract interface class Gcj02CoordinateConverter {
  Gcj02Coordinate fromWgs84({
    required double longitude,
    required double latitude,
  });
}

class MainlandGcj02CoordinateConverter implements Gcj02CoordinateConverter {
  const MainlandGcj02CoordinateConverter();

  static const _earthSemiMajorAxis = 6378245.0;
  static const _eccentricitySquared = 0.00669342162296594323;

  @override
  Gcj02Coordinate fromWgs84({
    required double longitude,
    required double latitude,
  }) {
    if (!_insideMainlandBounds(longitude, latitude)) {
      throw const FormatException('当前版本仅支持中国大陆范围内的附近定位');
    }

    var latitudeDelta = _transformLatitude(longitude - 105, latitude - 35);
    var longitudeDelta = _transformLongitude(longitude - 105, latitude - 35);
    final radians = latitude / 180 * math.pi;
    var magic = math.sin(radians);
    magic = 1 - _eccentricitySquared * magic * magic;
    final squareRoot = math.sqrt(magic);
    latitudeDelta =
        (latitudeDelta * 180) /
        ((_earthSemiMajorAxis * (1 - _eccentricitySquared)) /
            (magic * squareRoot) *
            math.pi);
    longitudeDelta =
        (longitudeDelta * 180) /
        (_earthSemiMajorAxis / squareRoot * math.cos(radians) * math.pi);
    return Gcj02Coordinate(
      longitude: longitude + longitudeDelta,
      latitude: latitude + latitudeDelta,
    );
  }

  static bool _insideMainlandBounds(double longitude, double latitude) {
    return longitude >= 72.004 &&
        longitude <= 137.8347 &&
        latitude >= 0.8293 &&
        latitude <= 55.8271;
  }

  static double _transformLatitude(double x, double y) {
    var result =
        -100 +
        2 * x +
        3 * y +
        0.2 * y * y +
        0.1 * x * y +
        0.2 * math.sqrt(x.abs());
    result +=
        (20 * math.sin(6 * x * math.pi) + 20 * math.sin(2 * x * math.pi)) *
        2 /
        3;
    result +=
        (20 * math.sin(y * math.pi) + 40 * math.sin(y / 3 * math.pi)) * 2 / 3;
    result +=
        (160 * math.sin(y / 12 * math.pi) + 320 * math.sin(y * math.pi / 30)) *
        2 /
        3;
    return result;
  }

  static double _transformLongitude(double x, double y) {
    var result =
        300 + x + 2 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * math.sqrt(x.abs());
    result +=
        (20 * math.sin(6 * x * math.pi) + 20 * math.sin(2 * x * math.pi)) *
        2 /
        3;
    result +=
        (20 * math.sin(x * math.pi) + 40 * math.sin(x / 3 * math.pi)) * 2 / 3;
    result +=
        (150 * math.sin(x / 12 * math.pi) + 300 * math.sin(x / 30 * math.pi)) *
        2 /
        3;
    return result;
  }
}

final gcj02CoordinateConverterProvider = Provider<Gcj02CoordinateConverter>(
  (_) => const MainlandGcj02CoordinateConverter(),
);
