// P2-M0 feasibility probe: how much of a planned bus ride can be drawn from
// busrouter's routes.min.json? Dart VM, not shipped. Written before the app
// loaded routes.min.json (it has since P2-M2, routeGeometryProvider).
// Results: docs/map-feasibility.md §5.
//
//   dart run tool/route_geometry_probe.dart              # download the 3 files
//   dart run tool/route_geometry_probe.dart --dir <dir>  # use local copies
//
// For every service direction the stops (services.min.json, in stop order) are
// matched to the direction's polyline: each stop gets the polyline positions
// within [tolerance] of it, and a dynamic programme picks the in-order path
// that matches the most stops with the least total offset. The polyline is
// tried as given, reversed, and (for loops whose geometry starts elsewhere)
// doubled. A ride board → alight is "drawable" when every hop between them is
// matched in order and no hop is more than [maxDetour] × its straight line.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

const base = 'https://data.busrouter.sg/v1';
const tolerance = 60.0; // metres from stop to polyline
const mergeWithin = 40.0; // metres along the line: one candidate per pass
const maxDetour = 3.0;
const earthRadius = 6371008.8;

Future<void> main(List<String> args) async {
  final dirIndex = args.indexOf('--dir');
  Future<Map<String, dynamic>> load(String name) async {
    final text = dirIndex >= 0
        ? File('${args[dirIndex + 1]}/$name.min.json').readAsStringSync()
        : (await http.get(Uri.parse('$base/$name.min.json'))).body;
    return jsonDecode(text) as Map<String, dynamic>;
  }

  final routes = await load('routes');
  final services = await load('services');
  final stops = await load('stops');
  Pt stop(String code) {
    final s = stops[code] as List; // [lng, lat, name, road]
    return Pt.of((s[1] as num).toDouble(), (s[0] as num).toDouble());
  }

  var directions = 0, full = 0, pairs = 0, drawablePairs = 0;
  final orientation = <String, int>{};
  final detours = <double>[];
  final matches = <String, (List<String>, Map<int, double>)>{};
  for (final MapEntry(key: service, value: v) in services.entries) {
    final dirs = ((v as Map)['routes'] as List).cast<List>();
    for (var d = 0; d < dirs.length; d++) {
      final codes = dirs[d].cast<String>().where(stops.containsKey).toList();
      final line = decodePolyline((routes[service] as List)[d] as String);
      directions++;
      var best = (name: '', m: <int, double>{});
      for (final (name, variant) in [
        ('as given', line),
        ('reversed', line.reversed.toList()),
        ('doubled', [...line, ...line]),
        ('reversed+doubled', [...line.reversed, ...line.reversed]),
      ]) {
        final m = matchStops(codes.map(stop).toList(), variant);
        if (m.length > best.m.length) best = (name: name, m: m);
        if (m.length == codes.length) break;
      }
      orientation.update(best.name, (n) => n + 1, ifAbsent: () => 1);
      if (best.m.length == codes.length) full++;
      matches['$service/$d'] = (codes, best.m);
      for (var i = 0; i + 1 < codes.length; i++) {
        pairs++;
        final (a, b) = (best.m[i], best.m[i + 1]);
        if (a == null || b == null || b < a) continue;
        drawablePairs++;
        final straight = stop(codes[i]).distanceTo(stop(codes[i + 1]));
        if (straight > 50) detours.add((b - a) / straight);
      }
    }
  }

  bool drawable(List<String> codes, Map<int, double> m, int i, int j) {
    for (var k = i; k < j; k++) {
      final (a, b) = (m[k], m[k + 1]);
      if (a == null || b == null || b < a) return false;
      final straight = stop(codes[k]).distanceTo(stop(codes[k + 1]));
      if (straight > 50 && (b - a) / straight > maxDetour) return false;
    }
    return true;
  }

  final random = math.Random(1);
  var rides = 0, drawableRides = 0;
  for (final (codes, m) in matches.values) {
    for (var t = 0; t < 10 && codes.length > 1; t++) {
      final i = random.nextInt(codes.length - 1);
      final j = math.min(codes.length - 1, i + 1 + random.nextInt(25));
      rides++;
      if (drawable(codes, m, i, j)) drawableRides++;
    }
  }

  detours.sort();
  String pct(int a, int b) => '${(100 * a / b).toStringAsFixed(1)}%';
  double q(double p) => detours[(p * (detours.length - 1)).round()];
  stdout.writeln(
    'busrouter routes.min.json geometry check '
    '(${DateTime.now().toUtc().toIso8601String()})',
  );
  stdout.writeln('services ${services.length}, directions $directions');
  stdout.writeln(
    'directions with every stop matched in order: $full '
    '(${pct(full, directions)})',
  );
  stdout.writeln('polyline orientation used: $orientation');
  stdout.writeln(
    'consecutive stop pairs drawable: $drawablePairs / $pairs '
    '(${pct(drawablePairs, pairs)})',
  );
  stdout.writeln(
    'along-line / straight-line per drawable hop: median '
    '${q(.5).toStringAsFixed(2)}, p95 ${q(.95).toStringAsFixed(2)}, '
    'p99 ${q(.99).toStringAsFixed(2)}',
  );
  stdout.writeln(
    'random rides (1-25 stops, 10 per direction, seed 1) drawable '
    'end to end: $drawableRides / $rides (${pct(drawableRides, rides)})',
  );
  for (final (svc, board, alight) in [('10', '03019', '14141')]) {
    for (var d = 0; d < 2; d++) {
      final entry = matches['$svc/$d'];
      if (entry == null) continue;
      final (codes, m) = entry;
      final (i, j) = (codes.indexOf(board), codes.indexOf(alight));
      if (i < 0 || j <= i) continue;
      stdout.writeln(
        'M3 smoke ride Bus $svc $board -> $alight (direction $d, '
        '${j - i} stops): drawable ${drawable(codes, m, i, j)}, '
        '${((m[j] ?? 0) - (m[i] ?? 0)).round()} m along the line',
      );
    }
  }
}

/// A point in metres on a local equirectangular plane around Singapore.
class Pt {
  const Pt(this.x, this.y);
  factory Pt.of(double lat, double lng) => Pt(
    lng * math.pi / 180 * earthRadius * math.cos(1.35 * math.pi / 180),
    lat * math.pi / 180 * earthRadius,
  );
  final double x, y;
  double distanceTo(Pt o) =>
      math.sqrt(math.pow(x - o.x, 2) + math.pow(y - o.y, 2));
}

/// Precision-5 Google polyline. `-(r >> 1) - 1`, not `~(r >> 1)`: the app
/// also runs on Web, where dart2js bitwise operators are unsigned 32-bit.
List<Pt> decodePolyline(String s) {
  final out = <Pt>[];
  var i = 0, lat = 0, lng = 0;
  int next() {
    var shift = 0, result = 0, b = 0;
    do {
      b = s.codeUnitAt(i++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    return (result & 1) != 0 ? -(result >> 1) - 1 : result >> 1;
  }

  while (i < s.length) {
    lat += next();
    lng += next();
    out.add(Pt.of(lat / 1e5, lng / 1e5));
  }
  return out;
}

/// Stop index → metres along [line] for the stops matched in order.
Map<int, double> matchStops(List<Pt> stops, List<Pt> line) {
  // Candidate positions along the line for each stop.
  final cumulative = <double>[0];
  for (var k = 0; k + 1 < line.length; k++) {
    cumulative.add(cumulative.last + line[k].distanceTo(line[k + 1]));
  }
  final candidates = [
    for (final p in stops)
      () {
        final found = <(double, double)>[]; // (along, offset)
        for (var k = 0; k + 1 < line.length; k++) {
          final (a, b) = (line[k], line[k + 1]);
          final dx = b.x - a.x, dy = b.y - a.y, l2 = dx * dx + dy * dy;
          final t = l2 == 0
              ? 0.0
              : (((p.x - a.x) * dx + (p.y - a.y) * dy) / l2).clamp(0.0, 1.0);
          final d = p.distanceTo(Pt(a.x + t * dx, a.y + t * dy));
          if (d <= tolerance) found.add((cumulative[k] + t * math.sqrt(l2), d));
        }
        found.sort((u, v) => u.$1.compareTo(v.$1));
        final merged = <(double, double)>[];
        for (final c in found) {
          if (merged.isNotEmpty && c.$1 - merged.last.$1 < mergeWithin) {
            if (c.$2 < merged.last.$2) merged.last = c;
          } else {
            merged.add(c);
          }
        }
        return merged;
      }(),
  ];

  // Longest in-order chain (most stops, then least total offset).
  final states =
      <({int stop, double along, int count, double cost, int prev})>[];
  for (var i = 0; i < candidates.length; i++) {
    final added =
        <({int stop, double along, int count, double cost, int prev})>[];
    for (final (along, d) in candidates[i]) {
      var best = (count: 1, cost: d, prev: -1);
      for (var s = 0; s < states.length; s++) {
        final st = states[s];
        if (st.along > along + 1) continue;
        final count = st.count + 1, cost = st.cost + d;
        if (count > best.count || (count == best.count && cost < best.cost)) {
          best = (count: count, cost: cost, prev: s);
        }
      }
      added.add((
        stop: i,
        along: along,
        count: best.count,
        cost: best.cost,
        prev: best.prev,
      ));
    }
    states.addAll(added);
  }
  if (states.isEmpty) return {};
  var end = 0;
  for (var s = 1; s < states.length; s++) {
    final (a, b) = (states[s], states[end]);
    if (a.count > b.count || (a.count == b.count && a.cost < b.cost)) end = s;
  }
  final result = <int, double>{};
  for (var s = end; s >= 0; s = states[s].prev) {
    result[states[s].stop] = states[s].along;
  }
  return result;
}
