/// Groups LTA MRT Station Exit records into stations. Pure Dart: shared by
/// tool/build_mrt_asset.dart (which writes the bundled asset) and the tests.
library;

import '../../../core/geo/geo.dart';
import '../domain/mrt.dart';

/// One exit record as published (`STATION_NA`, `EXIT_CODE`, point).
class RawMrtExit {
  const RawMrtExit({
    required this.stationName,
    required this.exitCode,
    required this.latitude,
    required this.longitude,
  });

  final String stationName;
  final String exitCode;
  final double latitude;
  final double longitude;
}

/// A code-only `STATION_NA` (e.g. `CC9`) and the station it was verified to be.
class CodeOnlyStation {
  const CodeOnlyStation(this.code, this.name, this.evidence);
  final String code;
  final String name;
  final String evidence;
}

/// Seven records in the dataset carry only a station code as `STATION_NA`.
/// Each is mapped **only** because OneMap (Singapore Land Authority) returns a
/// station labelled with exactly that code close to those exits (searched by
/// station name, 2026-10-02). Proximity alone was not treated as evidence.
const List<CodeOnlyStation> verifiedCodeOnlyStations = [
  CodeOnlyStation(
    'CC9',
    'PAYA LEBAR MRT STATION',
    'OneMap "PAYA LEBAR MRT STATION (CC9)", 69 m from these exits',
  ),
  CodeOnlyStation(
    'DT18',
    'TELOK AYER MRT STATION',
    'OneMap "TELOK AYER MRT STATION (DT18)", 85 m from these exits',
  ),
  CodeOnlyStation(
    'DT4',
    'HUME MRT STATION',
    'OneMap "HUME MRT STATION (DT4)", 58 m from these exits',
  ),
  CodeOnlyStation(
    'NE18',
    'PUNGGOL COAST MRT STATION',
    'OneMap "PUNGGOL COAST MRT STATION (NE18)", 60 m from these exits',
  ),
  CodeOnlyStation(
    'CC30',
    'KEPPEL MRT STATION',
    'OneMap "KEPPEL MRT STATION (CC30)", 50 m from these exits',
  ),
  CodeOnlyStation(
    'CC31',
    'CANTONMENT MRT STATION',
    'OneMap "CANTONMENT MRT STATION (CC31)", 75 m from these exits',
  ),
  CodeOnlyStation(
    'CC32',
    'PRINCE EDWARD ROAD MRT STATION',
    'OneMap "PRINCE EDWARD ROAD MRT STATION (CC32)", 41 m from these exits',
  ),
];

final RegExp _codeOnly = RegExp(r'^[A-Z]{2}\d{1,2}$');

/// True when a `STATION_NA` is only a station code, e.g. `CC9`.
bool isCodeOnlyStationName(String name) => _codeOnly.hasMatch(name.trim());

class GroupingResult {
  const GroupingResult({
    required this.stations,
    required this.exitCount,
    required this.duplicateExits,
    required this.mappedCodeOnly,
    required this.unverifiedCodeOnly,
  });

  final List<MrtStation> stations;

  /// Distinct exits kept.
  final int exitCount;

  /// Identical records (same station, exit code and position) dropped.
  final int duplicateExits;

  /// Code-only names replaced through [verifiedCodeOnlyStations].
  final List<String> mappedCodeOnly;

  /// Code-only names with no verified mapping: kept as separate stations
  /// named by their code, never merged into a neighbour.
  final List<String> unverifiedCodeOnly;
}

/// Groups exits by station name (after the verified code-only mapping),
/// drops identical duplicates, and sorts stations by name and exits by code
/// and position, so the same input always gives the same output.
GroupingResult groupMrtExits(
  Iterable<RawMrtExit> exits, {
  List<CodeOnlyStation> codeOnly = verifiedCodeOnlyStations,
}) {
  final mapping = {for (final c in codeOnly) c.code: c.name};
  final byName = <String, List<MrtExit>>{};
  final seen = <String>{};
  final mapped = <String>{};
  final unverified = <String>{};
  var duplicates = 0;

  for (final raw in exits) {
    var name = raw.stationName.trim();
    if (isCodeOnlyStationName(name)) {
      final verified = mapping[name];
      if (verified != null) {
        mapped.add(name);
        name = verified;
      } else {
        unverified.add(name);
      }
    }
    final key = '$name|${raw.exitCode}|${raw.latitude}|${raw.longitude}';
    if (!seen.add(key)) {
      duplicates++;
      continue;
    }
    byName
        .putIfAbsent(name, () => [])
        .add(
          MrtExit(
            code: raw.exitCode.trim(),
            position: LatLng(raw.latitude, raw.longitude),
          ),
        );
  }

  int byExit(MrtExit a, MrtExit b) {
    final c = a.code.compareTo(b.code);
    if (c != 0) return c;
    final lat = a.position.latitude.compareTo(b.position.latitude);
    return lat != 0
        ? lat
        : a.position.longitude.compareTo(b.position.longitude);
  }

  final names = byName.keys.toList()..sort();
  return GroupingResult(
    stations: [
      for (final name in names)
        MrtStation(name: name, exits: byName[name]!..sort(byExit)),
    ],
    exitCount: seen.length,
    duplicateExits: duplicates,
    mappedCodeOnly: mapped.toList()..sort(),
    unverifiedCodeOnly: unverified.toList()..sort(),
  );
}
