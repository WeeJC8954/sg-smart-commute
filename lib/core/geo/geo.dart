import 'dart:math' as math;

import '../config/app_config.dart';

/// WGS84 coordinate (guide §2). Latitude first, always.
class LatLng {
  const LatLng(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  bool get isFinite => latitude.isFinite && longitude.isFinite;

  @override
  bool operator ==(Object other) =>
      other is LatLng &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  // Never log precise coordinates outside debug builds (§14); callers decide.
  @override
  String toString() => 'LatLng($latitude, $longitude)';
}

/// Singapore bounding-box check (§5.2). Rejects non-finite values.
bool isWithinSingapore(LatLng p) =>
    p.isFinite &&
    p.latitude >= SgBounds.minLatitude &&
    p.latitude <= SgBounds.maxLatitude &&
    p.longitude >= SgBounds.minLongitude &&
    p.longitude <= SgBounds.maxLongitude;

const double _earthRadiusMeters = 6371000;

/// Great-circle distance in metres.
double haversineMeters(LatLng a, LatLng b) {
  double rad(double deg) => deg * math.pi / 180;
  final dLat = rad(b.latitude - a.latitude);
  final dLng = rad(b.longitude - a.longitude);
  final h =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(a.latitude)) *
          math.cos(rad(b.latitude)) *
          math.pow(math.sin(dLng / 2), 2);
  return 2 * _earthRadiusMeters * math.asin(math.min(1, math.sqrt(h)));
}
