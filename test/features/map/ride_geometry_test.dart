import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/core/geo/geo.dart';
import 'package:sg_smart_commute/features/map/domain/polyline_codec.dart';
import 'package:sg_smart_commute/features/map/domain/ride_geometry.dart';
import 'package:sg_smart_commute/features/map/domain/route_geometry.dart';

Map<String, dynamic> _fixture(String name) => jsonDecode(
  File('test/fixtures/busrouter/geometry/$name.json').readAsStringSync(),
) as Map<String, dynamic>;

final _routes = _fixture('routes');
final _services = _fixture('services');
final _stops = _fixture('stops');

RouteGeometry get geometry => RouteGeometry({
  for (final e in _routes.entries) e.key: (e.value as List).cast<String>(),
});

LatLng stopAt(String code) {
  final s = _stops[code] as List; // [lng, lat, name, road]
  return LatLng((s[1] as num).toDouble(), (s[0] as num).toDouble());
}

/// The planner's view of a ride: [from]..[to] of the direction's stop list.
MapRide ride(String service, int direction, int from, int to) {
  final codes =
      (((_services[service] as Map)['routes'] as List)[direction] as List)
          .cast<String>();
  return MapRide(
    service: service,
    sourceDirection: direction,
    boardIndex: from,
    stops: [for (final c in codes.sublist(from, to + 1)) stopAt(c)],
  );
}

int indexIn(String service, int direction, String code) =>
    ((((_services[service] as Map)['routes'] as List)[direction]) as List)
        .indexOf(code);

double lengthOf(List<LatLng> points) {
  var m = 0.0;
  for (var i = 0; i + 1 < points.length; i++) {
    m += haversineMeters(points[i], points[i + 1]);
  }
  return m;
}

void expectDrawn(RideLine line, MapRide r, double meters) {
  expect(line, isA<RideLineDrawn>(), reason: '$line');
  final points = (line as RideLineDrawn).points;
  expect(line.ride, r);
  expect(lengthOf(points), closeTo(meters, 5));
  // Starts at the boarding stop and ends at the alighting stop (on the line).
  expect(haversineMeters(points.first, r.stops.first), lessThanOrEqualTo(60));
  expect(haversineMeters(points.last, r.stops.last), lessThanOrEqualTo(60));
}

void expectDecodesTo(String encoded, List<LatLng> expected) {
  final decoded = decodePolyline(encoded);
  expect(decoded.length, expected.length);
  for (var i = 0; i < expected.length; i++) {
    expect(decoded[i].latitude, closeTo(expected[i].latitude, 1e-9));
    expect(decoded[i].longitude, closeTo(expected[i].longitude, 1e-9));
  }
}

void main() {
  test('Bus 10, 03019 → 14141 (M3 smoke ride): drawn, 4,426 m', () {
    final from = indexIn('10', 0, '03019');
    final r = ride('10', 0, from, from + 9);
    expect(r.stops.length, 10);
    expectDrawn(matchRide(r, geometry), r, 4426);
  });

  test('normal direction, geometry as given: 4/0 loop service 0 → 1', () {
    final r = ride('4', 0, 0, 1);
    expectDrawn(matchRide(r, geometry), r, 499);
  });

  test('closed loop whose geometry starts at another stop (doubled): '
      '115/0 0 → 1', () {
    final r = ride('115', 0, 0, 1);
    expectDrawn(matchRide(r, geometry), r, 325);
  });

  test('an open line is never doubled: 10/1 0 → 1 → notMatched '
      '(only the artificial join would match, a straight stand-in)', () {
    final line = matchRide(ride('10', 1, 0, 1), geometry);
    expect((line as RideLineUnavailable).gap, RideLineGap.notMatched);
  });

  test('geometry stored reversed: 46/1 0 → 1', () {
    final r = ride('46', 1, 0, 1);
    expectDrawn(matchRide(r, geometry), r, 65);
  });

  test('repeated stop: each occurrence gives its own slice', () {
    final first = ride('11', 0, 6, 8), second = ride('11', 0, 17, 19);
    expect(first.stops.first, second.stops.first); // both board at 80199
    expectDrawn(matchRide(first, geometry), first, 1088);
    expectDrawn(matchRide(second, geometry), second, 306);
  });

  test('geometry that does not fit the ride: markers only (2B/0 0 → 3)', () {
    final line = matchRide(ride('2B', 0, 0, 3), geometry);
    expect((line as RideLineUnavailable).gap, RideLineGap.notMatched);
  });

  test('missing service or direction → noGeometry', () {
    final r = ride('10', 0, 0, 1);
    final noService = MapRide(
      service: 'NOPE',
      sourceDirection: 0,
      boardIndex: 0,
      stops: r.stops,
    );
    final noDirection = MapRide(
      service: '10',
      sourceDirection: 5,
      boardIndex: 0,
      stops: r.stops,
    );
    for (final x in [noService, noDirection]) {
      expect(
        (matchRide(x, geometry) as RideLineUnavailable).gap,
        RideLineGap.noGeometry,
      );
    }
  });

  test('malformed polyline → malformedGeometry', () {
    final r = ride('10', 0, 0, 1);
    for (final bad in ['_p~iF~ps|U_', '_p~iF']) {
      final g = RouteGeometry({
        '10': [bad],
      });
      expect(
        (matchRide(r, g) as RideLineUnavailable).gap,
        RideLineGap.malformedGeometry,
      );
    }
  });

  group('synthetic', () {
    // A straight east–west line along latitude 1.3: (1.3, 103.80) →
    // (1.3, 103.81) → (1.3, 103.82), about 2.2 km (computed with a precision-5
    // encoder; decoded back below to these points).
    const line = '_||F_mpxR?o}@?o}@';
    final g = RouteGeometry({
      'S': [line],
    });
    MapRide on(List<LatLng> stops) =>
        MapRide(service: 'S', sourceDirection: 0, boardIndex: 0, stops: stops);

    test('the straight line literal decodes to its points', () {
      expectDecodesTo(line, const [
        LatLng(1.3, 103.80),
        LatLng(1.3, 103.81),
        LatLng(1.3, 103.82),
      ]);
    });

    test('stops in line order: drawn, sliced between them', () {
      final r = on(const [LatLng(1.3, 103.805), LatLng(1.3, 103.815)]);
      final drawn = matchRide(r, g) as RideLineDrawn;
      expect(drawn.points.first.longitude, closeTo(103.805, 1e-6));
      expect(drawn.points.last.longitude, closeTo(103.815, 1e-6));
      expect(lengthOf(drawn.points), closeTo(1112, 5));
    });

    test('a stop out of order (backwards between two others) → notMatched', () {
      final r = on(const [
        LatLng(1.3, 103.805),
        LatLng(1.3, 103.818),
        LatLng(1.3, 103.810),
      ]);
      expect(
        (matchRide(r, g) as RideLineUnavailable).gap,
        RideLineGap.notMatched,
      );
    });

    test('a stop farther than 60 m from the line → notMatched', () {
      final r = on(const [LatLng(1.3, 103.805), LatLng(1.3008, 103.815)]);
      // 0.0008° latitude ≈ 89 m off the line
      expect(
        (matchRide(r, g) as RideLineUnavailable).gap,
        RideLineGap.notMatched,
      );
    });

    test('a hop more than 3× its straight line → notMatched', () {
      // A U-shaped open line: (1.3, 103.80) → (1.3, 103.82) → (1.3009, 103.82)
      // → (1.3009, 103.80). The two stops are its two ends, 100 m apart, but
      // about 4.5 km apart along it. The ends are 100 m apart (> 60 m), so the
      // line is not closed and is never doubled.
      const u = '_||F_mpxR?_|BsD??~{B';
      expectDecodesTo(u, const [
        LatLng(1.3, 103.80),
        LatLng(1.3, 103.82),
        LatLng(1.3009, 103.82),
        LatLng(1.3009, 103.80),
      ]);
      final r = MapRide(
        service: 'U',
        sourceDirection: 0,
        boardIndex: 0,
        stops: const [LatLng(1.3, 103.80), LatLng(1.3009, 103.80)],
      );
      expect(
        (matchRide(
          r,
          RouteGeometry({
            'U': [u],
          }),
        ) as RideLineUnavailable).gap,
        RideLineGap.notMatched,
      );
    });

    // A closed out-and-back line whose return lane is about 30 m north of the
    // outbound lane (inside the 60 m tolerance), so every stop has two
    // candidate passes: (1.3, 103.80) → (1.3, 103.82) → (1.30027, 103.82) →
    // (1.30027, 103.80) → (1.3, 103.80).
    const outAndBack = '_||F_mpxR?_|Bu@??~{Bt@?';
    final loop = RouteGeometry({
      'L': [outAndBack],
    });
    MapRide onLoop(List<LatLng> stops) =>
        MapRide(service: 'L', sourceDirection: 0, boardIndex: 0, stops: stops);

    test('the out-and-back literal decodes to its points', () {
      expectDecodesTo(outAndBack, const [
        LatLng(1.3, 103.80),
        LatLng(1.3, 103.82),
        LatLng(1.30027, 103.82),
        LatLng(1.30027, 103.80),
        LatLng(1.3, 103.80),
      ]);
    });

    test('least-length chain among valid monotonic chains', () {
      final r = onLoop(const [LatLng(1.3, 103.805), LatLng(1.3, 103.815)]);
      final drawn = matchRide(r, loop) as RideLineDrawn;
      expect(lengthOf(drawn.points), closeTo(1112, 5));
      // The outbound pass, not a detour via the return lane.
      expect(drawn.points.first.latitude, closeTo(1.3, 1e-6));
    });

    test('the opposite ride uses the return pass, never a cross-pass mix', () {
      final r = onLoop(const [LatLng(1.3, 103.815), LatLng(1.3, 103.805)]);
      final drawn = matchRide(r, loop) as RideLineDrawn;
      expect(lengthOf(drawn.points), closeTo(1112, 5));
      for (final p in drawn.points) {
        expect(p.latitude, closeTo(1.30027, 1e-5));
      }
    });
  });
}
