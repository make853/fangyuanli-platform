import 'package:flutter/foundation.dart';

import 'plaza_models.dart';

enum GeoCoordinateSystem { gcj02, wgs84 }

enum GeoMotionState { stationary, walking, running, driving, unknown }

@immutable
class DevicePosition {
  const DevicePosition({
    required this.coordinateSystem,
    required this.longitude,
    required this.latitude,
    required this.accuracyMeters,
    required this.capturedAt,
    this.motionState = GeoMotionState.unknown,
  });

  final GeoCoordinateSystem coordinateSystem;
  final double longitude;
  final double latitude;
  final double accuracyMeters;
  final DateTime capturedAt;
  final GeoMotionState motionState;

  Map<String, dynamic> toRequestJson() => {
    'coordinateSystem': coordinateSystem.name,
    'longitude': longitude,
    'latitude': latitude,
    'accuracyMeters': accuracyMeters,
    'capturedAt': capturedAt.toUtc().toIso8601String(),
    'motionState': motionState.name,
  };
}

@immutable
class GeoAnchorState {
  const GeoAnchorState({
    required this.radiusMeters,
    required this.isReused,
    required this.recalculationPending,
  });

  factory GeoAnchorState.fromJson(Map<String, dynamic> json) {
    return GeoAnchorState(
      radiusMeters: json['radiusMeters'] as int,
      isReused: json['isReused'] as bool,
      recalculationPending: json['recalculationPending'] as bool,
    );
  }

  final int radiusMeters;
  final bool isReused;
  final bool recalculationPending;
}

@immutable
class GeoContext {
  const GeoContext({
    required this.locationContextToken,
    required this.expiresAt,
    required this.anchor,
    required this.plazas,
  });

  factory GeoContext.fromJson(Map<String, dynamic> json) {
    return GeoContext(
      locationContextToken: json['locationContextToken'] as String,
      expiresAt: DateTime.parse(json['expiresAt'] as String),
      anchor: GeoAnchorState.fromJson(
        Map<String, dynamic>.from(json['anchor'] as Map),
      ),
      plazas: [
        for (final item in json['plazas'] as List)
          PlazaSummary.fromJson(Map<String, dynamic>.from(item as Map)),
      ],
    );
  }

  final String locationContextToken;
  final DateTime expiresAt;
  final GeoAnchorState anchor;
  final List<PlazaSummary> plazas;

  bool get isExpired => !expiresAt.isAfter(DateTime.now().toUtc());
}
