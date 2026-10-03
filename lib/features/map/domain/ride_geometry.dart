import 'dart:math' as math;

import '../../../core/config/app_config.dart';
import '../../../core/geo/geo.dart';
import 'polyline_codec.dart';
import 'route_geometry.dart';

/// The bus ride the planner chose, as the map needs it (P2-M2).
class MapRide {
  const MapRide({
    required this.service,
    required this.sourceDirection,
    required this.boardIndex,
    required this.stops,
  });

  final String service;

  /// busrouter's direction index (BusService.sourceDirectionOf).
  final int sourceDirection;

  /// The planner's boarding occurrence (BusOption.boardIndex).
  final int boardIndex;

  /// Boarding … alighting stop positions, in ride order (at least 2).
  final List<LatLng> stops;

  @override
  bool operator ==(Object other) =>
      other is MapRide &&
      other.service == service &&
      other.sourceDirection == sourceDirection &&
      other.boardIndex == boardIndex &&
      _samePoints(other.stops, stops);

  @override
  int get hashCode => Object.hash(
    service,
    sourceDirection,
    boardIndex,
    Object.hashAll([
      for (final p in stops) Object.hash(p.latitude, p.longitude),
    ]),
  );
}

bool _samePoints(List<LatLng> a, List<LatLng> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].latitude != b[i].latitude || a[i].longitude != b[i].longitude) {
      return false;
    }
  }
  return true;
}

/// Why a ride has no line. Each is a degraded map, never a routing failure.
enum RideLineGap { noGeometry, malformedGeometry, notMatched }

sealed class RideLine {
  const RideLine(this.ride);

  /// The ride this result was worked out for. Draw it only for that ride.
  final MapRide ride;
}

final class RideLineDrawn extends RideLine {
  const RideLineDrawn(super.ride, this.points);

  /// The ride on the road, boarding end first (at least 2 points).
  final List<LatLng> points;
}

final class RideLineUnavailable extends RideLine {
  const RideLineUnavailable(super.ride, this.gap);
  final RideLineGap gap;
}

class RideMatchConfig {
  const RideMatchConfig({
    this.toleranceMeters = MapConfig.rideStopToleranceMeters,
    this.mergeWithinMeters = MapConfig.rideCandidateMergeMeters,
    this.maxDetour = MapConfig.rideMaxDetour,
    this.detourMinStraightMeters = MapConfig.rideDetourMinStraightMeters,
  });

  final double toleranceMeters;
  final double mergeWithinMeters;
  final double maxDetour;
  final double detourMinStraightMeters;
}

/// The ride's line on its route geometry, or why there is none. All or
/// nothing: every ride stop must match in order (docs/assumptions.md "Bus
/// ride line"); a straight stand-in is never drawn. Pure: no I/O.
RideLine matchRide(
  MapRide ride,
  RouteGeometry geometry, {
  RideMatchConfig config = const RideMatchConfig(),
}) {
  final encoded = geometry.encoded(ride.service, ride.sourceDirection);
  if (encoded == null) return RideLineUnavailable(ride, RideLineGap.noGeometry);
  final List<LatLng> line;
  try {
    line = decodePolyline(encoded);
  } on FormatException {
    return RideLineUnavailable(ride, RideLineGap.malformedGeometry);
  }
  if (line.length < 2 || ride.stops.length < 2) {
    return RideLineUnavailable(ride, RideLineGap.malformedGeometry);
  }
  // As given; stored backwards. A loop whose geometry starts at another stop
  // is doubled, but only when the line is closed: doubling an open line adds
  // a straight segment from its end back to its start, and a stop matched
  // there would be drawn as a straight stand-in (never drawn, D1).
  final reversed = line.reversed.toList();
  final closed =
      haversineMeters(line.first, line.last) <= config.toleranceMeters;
  for (final variant in [
    line,
    reversed,
    if (closed) ...[
      [...line, ...line],
      [...reversed, ...reversed],
    ],
  ]) {
    final points = _matchAndSlice(ride.stops, variant, config);
    if (points != null) return RideLineDrawn(ride, points);
  }
  return RideLineUnavailable(ride, RideLineGap.notMatched);
}

/// A point in metres on a local plane around Singapore (equirectangular;
/// error far below the 60 m tolerance at this latitude).
class _P {
  const _P(this.x, this.y);
  factory _P.of(LatLng p) => _P(
    p.longitude * _metresPerDegree * _cosLat,
    p.latitude * _metresPerDegree,
  );
  static const double _metresPerDegree = 6371008.8 * math.pi / 180;
  static final double _cosLat = math.cos(1.35 * math.pi / 180);
  final double x, y;
  double distanceTo(_P o) =>
      math.sqrt(math.pow(x - o.x, 2) + math.pow(y - o.y, 2));
}

/// One pass of the line near a stop: metres [along] the line, the segment
/// [k] and the fraction [t] along it, and the [offset] from the stop.
typedef _Hit = ({double along, int k, double t, double offset});

List<LatLng>? _matchAndSlice(
  List<LatLng> stops,
  List<LatLng> line,
  RideMatchConfig c,
) {
  final pts = [for (final p in line) _P.of(p)];
  final cumulative = <double>[0];
  for (var k = 0; k + 1 < pts.length; k++) {
    cumulative.add(cumulative.last + pts[k].distanceTo(pts[k + 1]));
  }
  final hits = <List<_Hit>>[];
  for (final s in stops) {
    final h = _hitsNear(_P.of(s), pts, cumulative, c);
    if (h.isEmpty) return null;
    hits.add(h);
  }

  // Least total along-line length over in-order chains, one hit per stop.
  var total = <double?>[for (final _ in hits[0]) 0];
  final from = <List<int>>[
    [for (final _ in hits[0]) -1],
  ];
  for (var i = 1; i < hits.length; i++) {
    final straight = haversineMeters(stops[i - 1], stops[i]);
    final next = List<double?>.filled(hits[i].length, null);
    final prev = List<int>.filled(hits[i].length, -1);
    for (var b = 0; b < hits[i].length; b++) {
      for (var a = 0; a < hits[i - 1].length; a++) {
        final before = total[a];
        if (before == null) continue;
        final hop = hits[i][b].along - hits[i - 1][a].along;
        if (hop <= 0) continue; // must move forward along the line
        if (straight > c.detourMinStraightMeters &&
            hop > c.maxDetour * straight) {
          continue;
        }
        final sum = before + hop;
        if (next[b] == null || sum < next[b]!) {
          next[b] = sum;
          prev[b] = a;
        }
      }
    }
    if (next.every((v) => v == null)) return null;
    total = next;
    from.add(prev);
  }

  var end = -1;
  for (var b = 0; b < total.length; b++) {
    if (total[b] != null && (end < 0 || total[b]! < total[end]!)) end = b;
  }
  var start = end;
  for (var i = hits.length - 1; i > 0; i--) {
    start = from[i][start];
  }
  return _slice(line, hits.first[start], hits.last[end]);
}

List<_Hit> _hitsNear(
  _P p,
  List<_P> pts,
  List<double> cumulative,
  RideMatchConfig c,
) {
  final found = <_Hit>[];
  for (var k = 0; k + 1 < pts.length; k++) {
    final a = pts[k], b = pts[k + 1];
    final dx = b.x - a.x, dy = b.y - a.y, l2 = dx * dx + dy * dy;
    final t = l2 == 0
        ? 0.0
        : (((p.x - a.x) * dx + (p.y - a.y) * dy) / l2).clamp(0.0, 1.0);
    final offset = p.distanceTo(_P(a.x + t * dx, a.y + t * dy));
    if (offset <= c.toleranceMeters) {
      found.add((
        along: cumulative[k] + t * math.sqrt(l2),
        k: k,
        t: t,
        offset: offset,
      ));
    }
  }
  found.sort((u, v) => u.along.compareTo(v.along));
  final merged = <_Hit>[];
  for (final h in found) {
    if (merged.isNotEmpty &&
        h.along - merged.last.along < c.mergeWithinMeters) {
      if (h.offset < merged.last.offset) merged.last = h;
    } else {
      merged.add(h);
    }
  }
  return merged;
}

LatLng _at(List<LatLng> line, int k, double t) {
  final a = line[k], b = line[k + 1];
  return LatLng(
    a.latitude + t * (b.latitude - a.latitude),
    a.longitude + t * (b.longitude - a.longitude),
  );
}

List<LatLng> _slice(List<LatLng> line, _Hit from, _Hit to) => [
  _at(line, from.k, from.t),
  for (var k = from.k + 1; k <= to.k; k++) line[k],
  _at(line, to.k, to.t),
];
