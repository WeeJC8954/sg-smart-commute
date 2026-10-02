// Milestone 3 real-data smoke check (Dart VM, not shipped).
//
//   dart run tool/journey_smoke.dart
//
// For each origin/destination pair: geocodes both ends with OneMap
// (tokenless) and uses the result chosen for that place (exact SEARCHVAL and
// POSTAL), never simply the first result; a place whose chosen result is
// missing is reported and skipped. Loads the live busrouter stops and
// services, and runs the app's own parser and planner. Every recommended
// option is then cross-checked against the RAW services.min.json with
// independent code: the board stop must occur before the alight stop in that
// service's direction, and the stop count must be the shortest such segment.
// The nearest MRT comes from the bundled asset and is checked against a
// brute-force pass over every exit in the raw asset JSON. Results go to stdout.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:sg_smart_commute/core/geo/geo.dart';
import 'package:sg_smart_commute/features/journey/data/busrouter_parser.dart';
import 'package:sg_smart_commute/features/journey/data/mrt_asset.dart';
import 'package:sg_smart_commute/features/journey/domain/bus_network.dart';
import 'package:sg_smart_commute/features/journey/domain/direct_bus_planner.dart';
import 'package:sg_smart_commute/features/journey/domain/mrt.dart';

/// A OneMap query and the one result chosen for it: exact `SEARCHVAL` and
/// `POSTAL` (`NIL` where OneMap has no postcode).
typedef Place = ({String query, String pick, String postal});

const List<(String, Place, Place)> pairs = [
  (
    'Straightforward direct',
    (
      query: 'Tampines Bus Interchange',
      pick: 'TAMPINES BUS INTERCHANGE',
      postal: '520512',
    ),
    (query: 'VivoCity', pick: 'VIVOCITY', postal: '098585'),
  ),
  (
    'Multiple services',
    (query: 'ION Orchard', pick: 'ION ORCHARD', postal: '238801'),
    (query: 'Bugis Junction', pick: 'BUGIS JUNCTION', postal: '188021'),
  ),
  (
    'No direct bus (expected)',
    (
      query: 'Changi Village',
      pick: 'MARKET & HAWKER CENTRE (BLKS 2 & 3 CHANGI VILLAGE ROAD)',
      postal: '500002',
    ),
    (query: 'Jurong Point', pick: 'JURONG POINT', postal: '648886'),
  ),
  (
    'Loop service',
    (
      query: 'Tampines Bus Interchange',
      pick: 'TAMPINES BUS INTERCHANGE',
      postal: '520512',
    ),
    (
      query: '390 Tampines Avenue 7',
      pick: '390 TAMPINES AVENUE 7 SINGAPORE 520390',
      postal: '520390',
    ),
  ),
  (
    'Walk preferable',
    (query: 'ION Orchard', pick: 'ION ORCHARD', postal: '238801'),
    (query: 'Wisma Atria', pick: 'WISMA ATRIA', postal: '238877'),
  ),
];

Future<Object?> getJson(String url) async {
  final r = await http.get(Uri.parse(url));
  if (r.statusCode != 200) throw StateError('$url → HTTP ${r.statusCode}');
  return jsonDecode(utf8.decode(r.bodyBytes));
}

Future<(String, LatLng)?> geocode(Place place) async {
  final uri = Uri.https('www.onemap.gov.sg', '/api/common/elastic/search', {
    'searchVal': place.query,
    'returnGeom': 'Y',
    'getAddrDetails': 'Y',
    'pageNum': '1',
  });
  // OneMap answered 429 after 3 quick calls on 2026-10-01: space calls out
  // and back off on 429 instead of failing the run.
  Map<String, dynamic>? json;
  for (var attempt = 0; json == null; attempt++) {
    await Future<void>.delayed(const Duration(seconds: 3));
    final r = await http.get(uri);
    if (r.statusCode == 429 && attempt < 4) {
      stdout.writeln(
        '  (OneMap 429 for "${place.query}"; '
        'backing off ${10 * (attempt + 1)} s)',
      );
      await Future<void>.delayed(Duration(seconds: 10 * (attempt + 1)));
      continue;
    }
    if (r.statusCode != 200) throw StateError('OneMap HTTP ${r.statusCode}');
    json = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }
  final results = (json['results'] as List).cast<Map<String, dynamic>>();
  final index = results.indexWhere(
    (r) => r['SEARCHVAL'] == place.pick && r['POSTAL'] == place.postal,
  );
  if (index < 0) {
    stdout.writeln(
      '  OneMap "${place.query}": chosen result not found among '
      '${results.map((r) => '${r['SEARCHVAL']} (${r['POSTAL']})').join('; ')}',
    );
    return null;
  }
  final chosen = results[index];
  return (
    '${chosen['SEARCHVAL']} (${chosen['POSTAL']}), '
        'result ${index + 1} of ${results.length}',
    LatLng(
      double.parse(chosen['LATITUDE'] as String),
      double.parse(chosen['LONGITUDE'] as String),
    ),
  );
}

/// Independent "no direct bus" check on the raw JSON: no service direction
/// has a stop within [radius] of [a] before a stop within [radius] of [b].
/// Raw stops are `[lng, lat, name, road]`.
String noDirectCrossCheck(
  Map<String, dynamic> rawStops,
  Map<String, dynamic> rawServices,
  LatLng a,
  LatLng b,
  double radius,
) {
  Set<String> near(LatLng p) => {
    for (final MapEntry(:key, :value) in rawStops.entries)
      if (haversineMeters(
            p,
            LatLng(
              ((value as List)[1] as num).toDouble(),
              (value[0] as num).toDouble(),
            ),
          ) <=
          radius)
        key,
  };
  final from = near(a), to = near(b);
  final hits = <String>[];
  for (final MapEntry(:key, :value) in rawServices.entries) {
    for (final route in ((value as Map<String, dynamic>)['routes'] as List)) {
      final stops = (route as List).cast<String>();
      final i = stops.indexWhere(from.contains);
      if (i >= 0 && stops.skip(i + 1).any(to.contains)) hits.add(key);
    }
  }
  return hits.isEmpty
      ? 'OK (${from.length} origin / ${to.length} destination stops within '
            '${radius.round()} m; no raw route connects them)'
      : 'FAIL: raw routes connect them: ${hits.join(', ')}';
}

/// Independent nearest-exit check: every exit in the raw asset JSON.
String mrtCrossCheck(Map<String, dynamic> raw, LatLng point, MrtSuggestion? s) {
  (String, String, double)? best;
  for (final st in (raw['stations'] as List).cast<Map<String, dynamic>>()) {
    for (final e in (st['exits'] as List).cast<Map<String, dynamic>>()) {
      final d = haversineMeters(
        point,
        LatLng((e['lat'] as num).toDouble(), (e['lng'] as num).toDouble()),
      );
      if (best == null || d < best.$3) {
        best = (st['name'] as String, e['exit'] as String, d);
      }
    }
  }
  final (name, exit, meters) = best!;
  if (meters > 1500) {
    return s == null
        ? 'OK (raw nearest exit ${meters.round()} m, beyond 1.5 km)'
        : 'FAIL: app suggests a station, raw nearest is ${meters.round()} m';
  }
  if (s == null) return 'FAIL: app found none, raw nearest is $name $exit';
  if (s.station.name != name || s.nearestExit.code != exit) {
    return 'FAIL: raw nearest is $name $exit (${meters.round()} m)';
  }
  return 'OK (raw nearest exit: $name $exit, ${meters.round()} m)';
}

/// Independent check against the raw JSON (not the app's parsed model).
String crossCheck(Map<String, dynamic> raw, BusOption o) {
  final routes =
      (raw[o.service.number] as Map<String, dynamic>)['routes'] as List;
  final route = (routes[o.direction] as List).cast<String>();
  int? best;
  for (var i = 0; i < route.length; i++) {
    if (route[i] != o.board.code) continue;
    final j = route.indexOf(o.alight.code, i + 1);
    if (j > i && (best == null || j - i < best)) best = j - i;
  }
  if (best == null) {
    return 'FAIL: ${o.alight.code} never follows ${o.board.code}';
  }
  if (best != o.stops) return 'FAIL: raw shortest $best ≠ planner ${o.stops}';
  return 'OK (raw direction ${o.direction}: ${o.board.code} → ${o.alight.code}, '
      '$best stops)';
}

Future<void> main() async {
  stdout.writeln('Run at ${DateTime.now().toUtc().toIso8601String()}');
  final stopsJson = await getJson(
    'https://data.busrouter.sg/v1/stops.min.json',
  );
  final servicesJson = await getJson(
    'https://data.busrouter.sg/v1/services.min.json',
  );
  final stops = parseBusrouterStops(stopsJson);
  final network = BusNetwork(
    stops: stops,
    services: parseBusrouterServices(servicesJson, stops),
  );
  stdout.writeln(
    'busrouter: ${network.stops.length} stops, '
    '${network.services.length} services',
  );
  final mrtJson = jsonDecode(
    await File('assets/mrt_stations.json').readAsString(),
  ) as Map<String, dynamic>;
  final mrt = parseMrtAsset(mrtJson);

  for (final (label, from, to) in pairs) {
    final a = await geocode(from);
    final b = await geocode(to);
    if (a == null || b == null) {
      stdout.writeln(
        '\n== $label: no confirmed OneMap result for '
        '"${a == null ? from.query : to.query}"; skipped',
      );
      continue;
    }
    final (fromName, origin) = a;
    final (toName, destination) = b;
    stdout
      ..writeln('\n== $label')
      ..writeln('From "${from.query}" → OneMap: $fromName $origin')
      ..writeln('To   "${to.query}" → OneMap: $toName $destination');
    final plan = planDirectBus(network, origin, destination);
    switch (plan) {
      case WalkOnly(:final walk):
        stdout.writeln(
          'WalkOnly: ${walk.label}, ${walk.straightLineMeters.round()} m straight line',
        );
      case NoNearbyStops(:final side, :final radiusMeters):
        stdout.writeln('NoNearbyStops: $side within ${radiusMeters.round()} m');
      case NoDirectBus(:final radiusMeters):
        stdout
          ..writeln('No direct bus found (radius ${radiusMeters.round()} m)')
          ..writeln(
            '    cross-check: ${noDirectCrossCheck(stopsJson as Map<String, dynamic>, servicesJson as Map<String, dynamic>, origin, destination, radiusMeters)}',
          );
      case DirectBusOptions(:final options, :final radiusMeters):
        stdout.writeln('Direct options (radius ${radiusMeters.round()} m):');
        for (final (i, o) in options.indexed) {
          stdout
            ..writeln(
              '  ${i == 0 ? 'Suggested' : 'Alternative'}: Bus ${o.service.number} '
              'toward ${o.towardName}${o.isLoop ? ' (loop)' : ''}; '
              '${o.walkToStop.label} to ${o.board.code} ${o.board.name}; '
              '${o.stops} stops; alight ${o.alight.code} ${o.alight.name}; '
              '${o.walkFromStop.label} to destination; score ${o.score}',
            )
            ..writeln(
              '    cross-check: ${crossCheck(servicesJson as Map<String, dynamic>, o)}',
            );
        }
    }
    for (final (end, point) in [
      ('origin', origin),
      ('destination', destination),
    ]) {
      final s = nearestMrtStation(mrt, point);
      stdout
        ..writeln(
          '  Nearest MRT ($end): '
          '${s == null ? 'none within 1.5 km' : '${s.station.name} via ${s.nearestExit.code}, ${s.walk.label}'}',
        )
        ..writeln('    cross-check: ${mrtCrossCheck(mrtJson, point, s)}');
    }
    await Future<void>.delayed(
      const Duration(seconds: 1),
    ); // be polite to OneMap
  }
}
