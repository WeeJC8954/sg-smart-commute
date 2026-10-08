import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/core/geo/geo.dart';
import 'package:sg_smart_commute/features/map/data/busrouter_routes_parser.dart';
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
      stops: r.stops,
    );
    final noDirection = MapRide(
      service: '10',
      sourceDirection: 5,
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

  test('a malformed line for one service fails only that service\'s ride', () {
    // Through the parser, as loaded: 46's lines are corrupt, the rest are the
    // captured file. The parser keeps lines encoded, so the file still loads.
    final g = parseBusrouterRoutes({
      ..._routes,
      '46': ['_p~iF~ps|U_', '_p~iF'],
    });
    final bad = ride('46', 1, 0, 1);
    expect(
      (matchRide(bad, g) as RideLineUnavailable).gap,
      RideLineGap.malformedGeometry,
    );
    final from = indexIn('10', 0, '03019');
    final good = ride('10', 0, from, from + 9);
    expectDrawn(matchRide(good, g), good, 4426);
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
        MapRide(service: 'S', sourceDirection: 0, stops: stops);

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
        MapRide(service: 'L', sourceDirection: 0, stops: stops);

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

  group('boarding occurrence (leadingStops)', () {
    test('leadingStopCount: the shortest unique context before boarding', () {
      // ['C','A','B'] is the shortest unique run ending at B (board 3).
      expect(leadingStopCount(['A', 'B', 'C', 'A', 'B'], 3, 4), 1);
      // ['A','B'] occurs twice and nothing precedes it: never unique.
      expect(leadingStopCount(['A', 'B', 'C', 'A', 'B'], 0, 1), 0);
      // Already unique.
      expect(leadingStopCount(['A', 'B', 'C', 'D'], 2, 3), 0);
      // Needs two leading stops: [A,B] and [C,A,B] occur twice.
      expect(
        leadingStopCount(['X', 'C', 'A', 'B', 'Y', 'C', 'A', 'B'], 6, 7),
        2,
      );
      // [B] and [A,B] each occur twice and nothing more precedes: never
      // unique, so the result is boardIndex (1).
      expect(leadingStopCount(['A', 'B', 'A', 'B'], 1, 1), 1);
      // [A,B] occurs twice but [B,A,B] once: unique at m = 1.
      expect(leadingStopCount(['A', 'B', 'A', 'B'], 2, 3), 1);
    });

    // An open line that passes A then B twice: pass 1 along latitude 1.3,
    // north to C, back west and south, then pass 2 along latitude 1.30036
    // (about 40 m north, inside the tolerance): (1.3, 103.80) → (1.3, 103.81)
    // → (1.31, 103.81) → (1.31, 103.80) → (1.30036, 103.80) →
    // (1.30036, 103.81).
    const twoPasses = '_||F_mpxR?o}@o}@??n}@f{@??o}@';
    final g = RouteGeometry({
      'T': [twoPasses],
    });
    const a = LatLng(1.3, 103.80), b = LatLng(1.3, 103.81);
    const c = LatLng(1.31, 103.81);
    const codes = ['A', 'B', 'C', 'A', 'B'];

    test('the two-pass literal decodes to its points', () {
      expectDecodesTo(twoPasses, const [
        LatLng(1.3, 103.80),
        LatLng(1.3, 103.81),
        LatLng(1.31, 103.81),
        LatLng(1.31, 103.80),
        LatLng(1.30036, 103.80),
        LatLng(1.30036, 103.81),
      ]);
    });

    test('the later occurrence is drawn on its own pass', () {
      final m = leadingStopCount(codes, 3, 4);
      expect(m, 1);
      final r = MapRide(
        service: 'T',
        sourceDirection: 0,
        stops: const [a, b],
        leadingStops: const [c],
      );
      final drawn = matchRide(r, g) as RideLineDrawn;
      for (final p in drawn.points) {
        expect(p.latitude, closeTo(1.30036, 1e-5));
      }
      expect(lengthOf(drawn.points), closeTo(1112, 5));
    });

    test('without leadingStops the same ride is drawn on pass 1', () {
      final r = MapRide(service: 'T', sourceDirection: 0, stops: const [a, b]);
      final drawn = matchRide(r, g) as RideLineDrawn;
      for (final p in drawn.points) {
        expect(p.latitude, closeTo(1.3, 1e-5));
      }
    });

    test('the first occurrence (no unique context) is drawn on pass 1', () {
      expect(leadingStopCount(codes, 0, 1), 0);
      final r = MapRide(service: 'T', sourceDirection: 0, stops: const [a, b]);
      final drawn = matchRide(r, g) as RideLineDrawn;
      for (final p in drawn.points) {
        expect(p.latitude, closeTo(1.3, 1e-5));
      }
    });

    test('a leading stop that is not on the line → notMatched', () {
      // 220 m off both lanes: all or nothing, so no ride line at all.
      final r = MapRide(
        service: 'T',
        sourceDirection: 0,
        stops: const [a, b],
        leadingStops: const [LatLng(1.302, 103.805)],
      );
      expect(
        (matchRide(r, g) as RideLineUnavailable).gap,
        RideLineGap.notMatched,
      );
    });

    test('the detour cap applies to the hop from a leading stop', () {
      // The U line of the synthetic group. The ride alone (top lane, west)
      // is fine; with a leading stop at the far end of the line, 565 m away
      // in a straight line but 3.4 km along it, the hop is capped.
      const u = '_||F_mpxR?_|BsD??~{B';
      final ug = RouteGeometry({
        'U': [u],
      });
      const stops = [LatLng(1.3009, 103.805), LatLng(1.3009, 103.80)];
      MapRide withLeading(List<LatLng> leading) => MapRide(
        service: 'U',
        sourceDirection: 0,
        stops: stops,
        leadingStops: leading,
      );
      expect(matchRide(withLeading(const []), ug), isA<RideLineDrawn>());
      expect(
        (matchRide(
          withLeading(const [LatLng(1.3, 103.80)]),
          ug,
        ) as RideLineUnavailable).gap,
        RideLineGap.notMatched,
      );
    });
  });

  group('loops are never gone round more than once', () {
    // A closed square about 1 km a side (4 km round), starting at its
    // south-west corner: (1.30, 103.80) → (1.30, 103.809) → (1.309, 103.809)
    // → (1.309, 103.80) → (1.30, 103.80).
    const square = '_||F_mpxR?gw@gw@??fw@fw@?';
    final g = RouteGeometry({
      'Q': [square],
    });
    const m1 = LatLng(1.30, 103.8045), m2 = LatLng(1.3045, 103.809);
    const m3 = LatLng(1.309, 103.8045), m4 = LatLng(1.3045, 103.80);
    MapRide on(List<LatLng> stops) =>
        MapRide(service: 'Q', sourceDirection: 0, stops: stops);

    test('the square literal decodes to its points', () {
      expectDecodesTo(square, const [
        LatLng(1.30, 103.80),
        LatLng(1.30, 103.809),
        LatLng(1.309, 103.809),
        LatLng(1.309, 103.80),
        LatLng(1.30, 103.80),
      ]);
    });

    test('once round and a quarter further → notMatched', () {
      final r = on(const [m1, m2, m3, m4, m1, m2]);
      expect(
        (matchRide(r, g) as RideLineUnavailable).gap,
        RideLineGap.notMatched,
      );
    });

    test('less than one round, across the line start → drawn', () {
      final r = on(const [m1, m2, m3, m4, LatLng(1.30, 103.802)]);
      final drawn = matchRide(r, g) as RideLineDrawn;
      expect(lengthOf(drawn.points), lessThan(4000));
      expect(lengthOf(drawn.points), greaterThan(3000));
    });
  });

  group('MapRide value equality', () {
    MapRide base({
      String service = 'S',
      int sourceDirection = 0,
      List<LatLng> stops = const [LatLng(1.3, 103.80), LatLng(1.3, 103.81)],
      List<LatLng> leadingStops = const [LatLng(1.3, 103.79)],
    }) => MapRide(
      service: service,
      sourceDirection: sourceDirection,
      stops: stops,
      leadingStops: leadingStops,
    );

    test('equal for equal fields, with equal hash codes', () {
      expect(base(), base());
      expect(base().hashCode, base().hashCode);
    });

    test('unequal when any field differs', () {
      final variants = [
        base(service: 'T'),
        base(sourceDirection: 1),
        base(stops: const [LatLng(1.3, 103.80), LatLng(1.3, 103.82)]),
        base(leadingStops: const []),
        base(leadingStops: const [LatLng(1.3, 103.78)]),
      ];
      for (final v in variants) {
        expect(v, isNot(base()));
      }
    });
  });

  group('terminus to terminus', () {
    // A wiggly open line of 40 points (about 8.7 km) from a seeded generator.
    // The ride's end stops lie just beyond each end of the line (so they
    // project to t = 0 and t = 1), with five stops on the line between: the
    // chain spans the whole line, equal to its length up to float rounding.
    List<LatLng> wiggly(int seed) {
      final rnd = math.Random(seed);
      return [
        for (var i = 0; i < 40; i++)
          LatLng(
            1.3 + 0.0003 * rnd.nextDouble(),
            103.80 + 0.002 * i + 0.0004 * rnd.nextDouble(),
          ),
      ];
    }

    String encode(List<LatLng> points) {
      final out = StringBuffer();
      void put(int v) {
        var z = v < 0 ? -2 * v - 1 : 2 * v;
        while (z >= 32) {
          out.writeCharCode((32 | (z & 31)) + 63);
          z >>= 5;
        }
        out.writeCharCode(z + 63);
      }

      var lat = 0, lng = 0;
      for (final p in points) {
        final a = (p.latitude * 1e5).round(), b = (p.longitude * 1e5).round();
        put(a - lat);
        put(b - lng);
        lat = a;
        lng = b;
      }
      return out.toString();
    }

    for (final stored in ['as stored', 'stored backwards']) {
      test('end stops beyond both ends, line $stored: drawn, whole line', () {
        var drawnCount = 0;
        for (var seed = 0; seed < 40; seed++) {
          final points = wiggly(seed);
          final encoded = encode(
            stored == 'as stored' ? points : points.reversed.toList(),
          );
          final line = decodePolyline(
            encoded,
          ); // the line as the matcher sees it
          final ordered = stored == 'as stored' ? line : line.reversed.toList();
          // A tenth of a segment (about 22 m) beyond each end, along it.
          final f0 = ordered[0], f1 = ordered[1];
          final l0 = ordered[ordered.length - 1];
          final l1 = ordered[ordered.length - 2];
          final stops = [
            LatLng(
              f0.latitude - 0.1 * (f1.latitude - f0.latitude),
              f0.longitude - 0.1 * (f1.longitude - f0.longitude),
            ),
            for (final i in [7, 14, 21, 28, 35]) ordered[i],
            LatLng(
              l0.latitude + 0.1 * (l0.latitude - l1.latitude),
              l0.longitude + 0.1 * (l0.longitude - l1.longitude),
            ),
          ];
          final r = MapRide(service: 'W', sourceDirection: 0, stops: stops);
          final result = matchRide(
            r,
            RouteGeometry({
              'W': [encoded],
            }),
          );
          expect(result, isA<RideLineDrawn>(), reason: 'seed $seed');
          expect(
            lengthOf((result as RideLineDrawn).points),
            closeTo(lengthOf(line), 1),
            reason: 'seed $seed',
          );
          drawnCount++;
        }
        expect(drawnCount, 40);
      });
    }
  });
}
