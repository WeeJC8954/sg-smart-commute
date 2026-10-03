import '../../../core/config/app_config.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/geo/geo.dart';
import '../domain/bus_network.dart';

const StaticDataset _dataset = StaticDataset.busRoutes;

/// Parses busrouter `stops.min.json`: `{code: [lng, lat, name, road]}`
/// (guide v2.1 §9.1). **Longitude comes first**: it is converted to a
/// latitude-first [LatLng] here, and nowhere else.
///
/// Entries that are not `[number, number, string, string]`, or whose
/// coordinates fall outside [TransportDataBounds] (which also catches a
/// lat/lng swap), are dropped. Throws [StaticDataUnavailable] if the top level
/// is not an object, nothing valid remains, or more than
/// [BusrouterValidation.maxInvalidShare] of entries are invalid.
Map<String, BusStop> parseBusrouterStops(Object? json) {
  if (json is! Map<String, dynamic> || json.isEmpty) {
    throw const StaticDataUnavailable(_dataset, 'stops: not an object');
  }
  final stops = <String, BusStop>{};
  var invalid = 0;
  json.forEach((code, value) {
    final stop = _stop(code, value);
    if (stop == null) {
      invalid++;
    } else {
      stops[code] = stop;
    }
  });
  _checkShare('stops', invalid, json.length, stops.isEmpty);
  return stops;
}

BusStop? _stop(String code, Object? value) {
  if (code.isEmpty || value is! List || value.length < 4) return null;
  final [lng, lat, name, road, ...] = value;
  if (lng is! num || lat is! num || name is! String || road is! String) {
    return null;
  }
  final p = LatLng(lat.toDouble(), lng.toDouble());
  if (!isWithinTransportBounds(p)) return null;
  return BusStop(code: code, position: p, name: name, road: road);
}

/// Parses busrouter `services.min.json`: `{number: {name, routes: [[codes]…]}}`
/// with one or two ordered stop lists (one per direction).
///
/// Stop codes missing from [stops] are removed from a route; a route with
/// fewer than 2 stops left is dropped, and a service with no routes left (or
/// a malformed entry) is invalid. Same failure rule as the stops.
Map<String, BusService> parseBusrouterServices(
  Object? json,
  Map<String, BusStop> stops,
) {
  if (json is! Map<String, dynamic> || json.isEmpty) {
    throw const StaticDataUnavailable(_dataset, 'services: not an object');
  }
  final services = <String, BusService>{};
  var invalid = 0;
  json.forEach((number, value) {
    final service = _service(number, value, stops);
    if (service == null) {
      invalid++;
    } else {
      services[number] = service;
    }
  });
  _checkShare('services', invalid, json.length, services.isEmpty);
  return services;
}

BusService? _service(String number, Object? value, Map<String, BusStop> stops) {
  if (number.isEmpty || value is! Map<String, dynamic>) return null;
  final name = value['name'];
  final routes = value['routes'];
  if (name is! String || routes is! List || routes.isEmpty) return null;
  if (routes.length > 2) return null;

  final directions = <List<String>>[];
  final source = <int>[];
  for (var d = 0; d < routes.length; d++) {
    final route = routes[d];
    if (route is! List || route.any((c) => c is! String)) return null;
    final known = [
      for (final code in route.cast<String>())
        if (stops.containsKey(code)) code,
    ];
    if (known.length >= 2) {
      directions.add(known);
      source.add(d);
    }
  }
  if (directions.isEmpty) return null;
  return BusService(
    number: number,
    name: name,
    directions: directions,
    sourceDirections: source.length == routes.length ? null : source,
  );
}

void _checkShare(String what, int invalid, int total, bool nothingValid) {
  if (nothingValid) {
    throw StaticDataUnavailable(_dataset, '$what: no valid entries');
  }
  if (invalid / total > BusrouterValidation.maxInvalidShare) {
    throw StaticDataUnavailable(
      _dataset,
      '$what: $invalid of $total entries invalid',
    );
  }
}
