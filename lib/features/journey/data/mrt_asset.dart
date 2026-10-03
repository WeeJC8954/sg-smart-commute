/// The bundled MRT station asset format (`assets/mrt_stations.json`), written
/// by tool/build_mrt_asset.dart and read by the app. Pure Dart.
library;

import '../../../core/config/app_config.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/geo/geo.dart';
import '../domain/mrt.dart';

const StaticDataset _dataset = StaticDataset.mrtStations;

/// Encodes stations for the asset. Coordinates are rounded to 6 decimals
/// (~0.1 m) so output is stable.
List<Map<String, Object>> encodeMrtStations(List<MrtStation> stations) => [
  for (final s in stations)
    {
      'name': s.name,
      'exits': [
        for (final e in s.exits)
          {
            'exit': e.code,
            'lat': double.parse(e.position.latitude.toStringAsFixed(6)),
            'lng': double.parse(e.position.longitude.toStringAsFixed(6)),
          },
      ],
    },
];

/// Parses the asset's `stations` list. Throws [StaticDataUnavailable] if the
/// shape is wrong, a station has no exits, or a coordinate is outside
/// [TransportDataBounds]. Unlike the live busrouter data, the asset is
/// generated and reviewed, so any invalid entry fails the whole asset.
List<MrtStation> parseMrtAsset(Object? json) {
  if (json is! Map<String, dynamic>) {
    throw const StaticDataUnavailable(_dataset, 'not an object');
  }
  final stations = json['stations'];
  if (stations is! List || stations.isEmpty) {
    throw const StaticDataUnavailable(_dataset, 'no stations');
  }
  return [for (final s in stations) _station(s)];
}

MrtStation _station(Object? s) {
  if (s is! Map<String, dynamic>) {
    throw const StaticDataUnavailable(_dataset, 'station is not an object');
  }
  final name = s['name'];
  final exits = s['exits'];
  if (name is! String || name.isEmpty || exits is! List || exits.isEmpty) {
    throw const StaticDataUnavailable(_dataset, 'station without name/exits');
  }
  return MrtStation(name: name, exits: [for (final e in exits) _exit(e)]);
}

MrtExit _exit(Object? e) {
  if (e is! Map<String, dynamic>) {
    throw const StaticDataUnavailable(_dataset, 'exit is not an object');
  }
  final code = e['exit'];
  final lat = e['lat'];
  final lng = e['lng'];
  if (code is! String || lat is! num || lng is! num) {
    throw const StaticDataUnavailable(_dataset, 'exit fields');
  }
  final p = LatLng(lat.toDouble(), lng.toDouble());
  if (!isWithinTransportBounds(p)) {
    throw const StaticDataUnavailable(_dataset, 'exit outside range');
  }
  return MrtExit(code: code, position: p);
}
