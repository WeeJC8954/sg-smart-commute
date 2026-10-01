// Milestone 3 real-data smoke check (Dart VM, not shipped).
//
//   dart run tool/journey_smoke.dart
//
// For each origin/destination pair: geocodes both ends with OneMap
// (tokenless, first result, printed), loads the live busrouter stops and
// services, and runs the app's own parser and planner. Every recommended
// option is then cross-checked against the RAW services.min.json with
// independent code: the board stop must occur before the alight stop in that
// service's direction, and the stop count must be the shortest such segment.
// The nearest MRT comes from the bundled asset. Results go to stdout.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:sg_smart_commute/core/geo/geo.dart';
import 'package:sg_smart_commute/features/journey/data/busrouter_parser.dart';
import 'package:sg_smart_commute/features/journey/data/mrt_asset.dart';
import 'package:sg_smart_commute/features/journey/domain/bus_network.dart';
import 'package:sg_smart_commute/features/journey/domain/direct_bus_planner.dart';
import 'package:sg_smart_commute/features/journey/domain/mrt.dart';

const pairs = [
  ('Straightforward direct', 'Tampines Bus Interchange', 'VivoCity'),
  ('Multiple services', 'ION Orchard', 'Bugis Junction'),
  ('No direct bus (expected)', 'Changi Village', 'Jurong Point'),
  ('Loop service', 'Tampines Bus Interchange', '390 Tampines Avenue 7'),
  ('Walk preferable', 'ION Orchard', 'Wisma Atria'),
];

Future<Object?> getJson(String url) async {
  final r = await http.get(Uri.parse(url));
  if (r.statusCode != 200) throw StateError('$url → HTTP ${r.statusCode}');
  return jsonDecode(utf8.decode(r.bodyBytes));
}

Future<(String, LatLng)?> geocode(String query) async {
  final uri = Uri.https('www.onemap.gov.sg', '/api/common/elastic/search', {
    'searchVal': query,
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
        '  (OneMap 429 for "$query"; backing off ${10 * (attempt + 1)} s)',
      );
      await Future<void>.delayed(Duration(seconds: 10 * (attempt + 1)));
      continue;
    }
    if (r.statusCode != 200) throw StateError('OneMap HTTP ${r.statusCode}');
    json = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }
  final results = json['results'] as List;
  if (results.isEmpty) return null;
  final first = results.first as Map<String, dynamic>;
  return (
    '${first['SEARCHVAL']} (${first['POSTAL']})',
    LatLng(
      double.parse(first['LATITUDE'] as String),
      double.parse(first['LONGITUDE'] as String),
    ),
  );
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
  final mrt = parseMrtAsset(
    jsonDecode(await File('assets/mrt_stations.json').readAsString()),
  );

  for (final (label, from, to) in pairs) {
    final a = await geocode(from);
    final b = await geocode(to);
    if (a == null || b == null) {
      stdout.writeln(
        '\n== $label: OneMap found nothing for "${a == null ? from : to}"; '
        'skipped',
      );
      continue;
    }
    final (fromName, origin) = a;
    final (toName, destination) = b;
    stdout
      ..writeln('\n== $label')
      ..writeln('From "$from" → OneMap: $fromName $origin')
      ..writeln('To   "$to" → OneMap: $toName $destination');
    final plan = planDirectBus(network, origin, destination);
    switch (plan) {
      case WalkOnly(:final walk):
        stdout.writeln(
          'WalkOnly: ${walk.label}, ${walk.straightLineMeters.round()} m straight line',
        );
      case NoNearbyStops(:final side, :final radiusMeters):
        stdout.writeln('NoNearbyStops: $side within ${radiusMeters.round()} m');
      case NoDirectBus(:final radiusMeters):
        stdout.writeln(
          'No direct bus found (radius ${radiusMeters.round()} m)',
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
      stdout.writeln(
        '  Nearest MRT ($end): '
        '${s == null ? 'none within 1.5 km' : '${s.station.name} via ${s.nearestExit.code}, ${s.walk.label}'}',
      );
    }
    await Future<void>.delayed(
      const Duration(seconds: 1),
    ); // be polite to OneMap
  }
}
