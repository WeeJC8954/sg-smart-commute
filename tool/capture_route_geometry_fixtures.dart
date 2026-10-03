// Dev-only (not shipped): downloads busrouter's routes/services/stops once
// and writes the P2-M2 geometry fixture subset. Run:
//   dart run tool/capture_route_geometry_fixtures.dart
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const services = ['10', '46', '4', '11', '2B', '115'];
const base = 'https://data.busrouter.sg/v1';
const out = 'test/fixtures/busrouter/geometry';

/// A planned test case: [service]/[dir], boarding at [board], alighting at
/// [alight] (indices into the direction's stop list). The stop codes at those
/// indices are read from the captured data and written to PROVENANCE.md.
/// A null [board] means "the index of [boardCode]" (service 10 has 03019 at
/// a position the plan does not fix).
class _Case {
  const _Case(
    this.service,
    this.dir,
    this.board,
    this.alight, {
    this.boardCode,
    this.alightOffset,
    required this.expect,
  });
  final String service;
  final int dir;
  final int? board;
  final int? alight;
  final String? boardCode;
  final int? alightOffset;
  final String expect;
}

const _cases = [
  _Case(
    '10',
    0,
    null,
    null,
    boardCode: '03019',
    alightOffset: 9,
    expect: '03019 -> 14141',
  ),
  _Case('115', 0, 0, 1, expect: '63221 -> 63231'),
  _Case('10', 1, 0, 1, expect: '16009 -> 16089'),
  _Case('46', 1, 0, 1, expect: '77009 -> 77321'),
  _Case('4', 0, 0, 1, expect: '75009 -> 76191'),
  _Case('11', 0, 6, 8, expect: '80199 at 6 and 17'),
  _Case('11', 0, 17, 19, expect: '80199 at 6 and 17'),
  _Case('2B', 0, 0, 3, expect: '99009 -> 99039'),
];

Future<void> main() async {
  Future<Map<String, dynamic>> get(String name) async {
    final r = await http.get(Uri.parse('$base/$name.min.json'));
    if (r.statusCode != 200) throw StateError('$name: HTTP ${r.statusCode}');
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  final routes = await get('routes');
  final svc = await get('services');
  final stops = await get('stops');
  final codes = <String>{
    for (final s in services)
      for (final dir in (svc[s] as Map)['routes'] as List)
        ...(dir as List).cast<String>(),
  };
  const encoder = JsonEncoder.withIndent(' ');
  Directory(out).createSync(recursive: true);
  File('$out/routes.json').writeAsStringSync(
    encoder.convert({for (final s in services) s: routes[s]}),
  );
  File(
    '$out/services.json',
  ).writeAsStringSync(encoder.convert({for (final s in services) s: svc[s]}));
  File('$out/stops.json').writeAsStringSync(
    encoder.convert({for (final c in codes.toList()..sort()) c: stops[c]}),
  );
  final captured = DateTime.now().toUtc().toIso8601String();
  File('$out/PROVENANCE.md').writeAsStringSync(_provenance(svc, captured));
  stdout.writeln(
    'wrote ${services.length} services, ${codes.length} stops ($captured)',
  );
}

String _provenance(Map<String, dynamic> svc, String captured) {
  List<String> dirStops(String s, int dir) =>
      (((svc[s] as Map)['routes'] as List)[dir] as List).cast<String>();

  final rows = StringBuffer();
  for (final c in _cases) {
    final list = dirStops(c.service, c.dir);
    final board = c.board ?? list.indexOf(c.boardCode!);
    final alight = c.alight ?? board + c.alightOffset!;
    final bCode = board >= 0 && board < list.length ? list[board] : '?';
    final aCode = alight >= 0 && alight < list.length ? list[alight] : '?';
    rows.writeln(
      '| ${c.service}/${c.dir} | $board -> $alight | $bCode -> $aCode '
      '| ${c.expect} |',
    );
  }
  final sizes = [
    for (final s in services)
      '$s: ${(svc[s] as Map)['routes'].length} direction(s)',
  ].join(', ');
  return '''
# Geometry fixtures: provenance

Captured from live busrouter, a subset of three files, keyed exactly as the
live data (routes: service -> encoded polylines; services: service -> {name,
routes}; stops: code -> [lng, lat, name, road]).

- https://data.busrouter.sg/v1/routes.min.json
- https://data.busrouter.sg/v1/services.min.json
- https://data.busrouter.sg/v1/stops.min.json

Captured at (UTC): $captured

Command (regenerates these files and this one): `dart run tool/capture_route_geometry_fixtures.dart`

Services captured: ${services.join(', ')} ($sizes).

## Planned test cases

Indices are positions in the direction's stop list in `services.json`. The
codes are as found in the captured data; "expected" is what the plan assumed.

| Service/dir | Board -> alight index | Stop codes as captured | Expected |
| --- | --- | --- | --- |
$rows''';
}
