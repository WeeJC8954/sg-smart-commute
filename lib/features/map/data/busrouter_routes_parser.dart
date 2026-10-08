import '../../../core/config/app_config.dart';
import '../../../core/errors/app_failure.dart';
import '../../journey/data/busrouter_parser.dart';
import '../domain/route_geometry.dart';

const StaticDataset _dataset = StaticDataset.busRouteGeometry;

/// Parses busrouter `routes.min.json`: `{service: [encoded dir 0, encoded
/// dir 1?]}`, one Google-encoded polyline per busrouter direction.
///
/// The polylines are kept encoded: only the one a ride needs is decoded, in
/// the matcher. An entry that is not a list of one or two strings, or has a
/// line over [BusrouterValidation.maxEncodedLineLength], is dropped.
/// Throws [StaticDataUnavailable] if the top level is not an object, nothing
/// valid remains, or more than [BusrouterValidation.maxInvalidShare] of
/// entries are invalid (same rule as the stops and services).
RouteGeometry parseBusrouterRoutes(Object? json) {
  if (json is! Map<String, dynamic> || json.isEmpty) {
    throw const StaticDataUnavailable(_dataset, 'routes: not an object');
  }
  final encoded = <String, List<String>>{};
  var invalid = 0;
  json.forEach((service, value) {
    final lines = _lines(service, value);
    if (lines == null) {
      invalid++;
    } else {
      encoded[service] = lines;
    }
  });
  checkInvalidShare(_dataset, 'routes', invalid, json.length, encoded.isEmpty);
  return RouteGeometry(encoded);
}

List<String>? _lines(String service, Object? value) {
  if (service.isEmpty || value is! List) return null;
  if (value.isEmpty || value.length > 2) return null;
  if (value.any(
    (line) =>
        line is! String ||
        line.length > BusrouterValidation.maxEncodedLineLength,
  )) {
    return null;
  }
  return value.cast<String>();
}
