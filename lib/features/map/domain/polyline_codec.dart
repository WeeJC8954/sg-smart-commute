import '../../../core/geo/geo.dart';

/// Decodes a precision-5 Google encoded polyline (busrouter
/// routes.min.json). Throws [FormatException] when [encoded] is malformed.
///
/// Web-safe: dart2js bitwise operators are unsigned 32-bit, so a negative
/// delta is `-(result >> 1) - 1`, never `~(result >> 1)` (which turns every
/// negative delta into about +2^32 on the Web; found in the P2-M0 spike).
List<LatLng> decodePolyline(String encoded) {
  final points = <LatLng>[];
  var index = 0, lat = 0, lng = 0;

  int next() {
    var shift = 0, result = 0;
    while (true) {
      if (index >= encoded.length) {
        throw FormatException('truncated polyline', encoded, index);
      }
      final chunk = encoded.codeUnitAt(index++) - 63;
      if (chunk < 0 || chunk > 63) {
        throw FormatException('invalid polyline character', encoded, index - 1);
      }
      result |= (chunk & 0x1f) << shift;
      if (chunk < 0x20) break;
      shift += 5;
      if (shift > 25) {
        throw FormatException('polyline value too long', encoded, index);
      }
    }
    return (result & 1) != 0 ? -(result >> 1) - 1 : result >> 1;
  }

  while (index < encoded.length) {
    lat += next();
    if (index >= encoded.length) {
      throw FormatException('latitude without longitude', encoded, index);
    }
    lng += next();
    points.add(LatLng(lat / 1e5, lng / 1e5));
  }
  return points;
}
