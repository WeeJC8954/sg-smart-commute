// Direct-bus planner (guide v2.1 §9.2–§9.4). Synthetic networks with stops at
// known metre offsets from a base point, so walks, stop counts and scores are
// exact. Real busrouter routes (loop 4, one-direction 184, repeated stops in
// 265 and 647) are covered in busrouter_real_routes_test.dart.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/core/geo/geo.dart';
import 'package:sg_smart_commute/features/journey/domain/bus_network.dart';
import 'package:sg_smart_commute/features/journey/domain/direct_bus_planner.dart';
import 'package:sg_smart_commute/features/journey/domain/walking.dart';

const base = LatLng(1.3000, 103.8000);

/// A point [east] / [north] metres from [base].
LatLng at(double east, double north) => LatLng(
  base.latitude + north / 111320,
  base.longitude + east / (111320 * math.cos(base.latitude * math.pi / 180)),
);

/// Origin at x = 0; destination at x = 2000 m (far beyond walk-only).
final origin = at(0, 0);
final destination = at(2000, 0);

BusStop stop(String code, double east, double north) => BusStop(
  code: code,
  position: at(east, north),
  name: 'Stop $code',
  road: 'Road',
);

BusService service(String number, List<List<String>> directions) =>
    BusService(number: number, name: 'Svc $number', directions: directions);

BusNetwork network(List<BusStop> stops, List<BusService> services) =>
    BusNetwork(
      stops: {for (final s in stops) s.code: s},
      services: {for (final s in services) s.number: s},
    );

/// Stops: O* near the origin, D* near the destination, X* far from both.
final o1 = stop('O1', 50, 0); // ~1 min walk
final o2 = stop('O2', 0, 250); // ~5 min walk
final oFar = stop('O3', 0, 600); // only inside 800 m
final d1 = stop('D1', 2050, 0); // ~1 min walk
final d2 = stop('D2', 2000, 250); // ~5 min walk
final x1 = stop('X1', 700, 0);
final x2 = stop('X2', 1000, 0);
final x3 = stop('X3', 1300, 0);

List<BusOption> optionsOf(JourneyPlan plan) =>
    (plan as DirectBusOptions).options;

void main() {
  group('walking estimate (§9.3)', () {
    test('ceil(haversine × 1.3 / 80)', () {
      final a = at(0, 0);
      expect(WalkEstimate.between(a, a).minutes, 0);
      // 61 m × 1.3 = 79.3 m → 1 min; 62 m × 1.3 = 80.6 m → 2 min.
      expect(WalkEstimate.between(a, at(61, 0)).minutes, 1);
      expect(WalkEstimate.between(a, at(62, 0)).minutes, 2);
      // 400 m × 1.3 = 520 m → 6.5 → 7 min.
      final w = WalkEstimate.between(a, at(400, 0));
      expect(w.straightLineMeters, closeTo(400, 0.5));
      expect(w.walkMeters, closeTo(520, 0.7));
      expect(w.minutes, 7);
      expect(w.label, '~7 min walk (est.)');
    });

    test('detour factor and speed are configurable', () {
      final w = WalkEstimate.between(
        at(0, 0),
        at(390, 0),
        detourFactor: 1,
        metersPerMinute: 100,
      );
      expect(w.minutes, 4); // 3.9 → 4
      expect(WalkEstimate.between(at(0, 0), at(390, 0)).minutes, 7);
    });
  });

  group('walk-only short journeys', () {
    test('≤ 300 m apart → walk instead of bus', () {
      final plan = planDirectBus(
        network(
          [o1, d1],
          [
            service('1', [
              ['O1', 'D1'],
            ]),
          ],
        ),
        at(0, 0),
        at(290, 0),
      );
      expect(plan, isA<WalkOnly>());
      expect((plan as WalkOnly).walk.minutes, 5); // 290 × 1.3 / 80 = 4.7
    });

    test('just over 300 m → the planner runs', () {
      final plan = planDirectBus(
        network(
          [o1, d1],
          [
            service('1', [
              ['O1', 'D1'],
            ]),
          ],
        ),
        at(0, 0),
        at(310, 0),
      );
      expect(plan, isNot(isA<WalkOnly>()));
    });
  });

  group('basic matching', () {
    test(
      'two-direction service: boards in the direction where o precedes d',
      () {
        final net = network(
          [o1, x1, x2, d1],
          [
            service('10', [
              ['O1', 'X1', 'X2', 'D1'],
              ['D1', 'X2', 'X1', 'O1'],
            ]),
          ],
        );
        final best = optionsOf(planDirectBus(net, origin, destination)).single;
        expect(best.service.number, '10');
        expect(best.direction, 0);
        expect(best.board.code, 'O1');
        expect(best.alight.code, 'D1');
        expect(best.stops, 3);
        expect(best.walkToStop.minutes, 1);
        expect(best.walkFromStop.minutes, 1);
        expect(best.score, 1 + 1 + 1.5 * 3);
        expect(best.towardName, 'Stop D1'); // last stop of direction 0's list
      },
    );

    test('opposite-side stops: the wrong-side stop is never recommended', () {
      // O1/D1 are on direction 0's side; O1x/D1x are across the road and
      // only in direction 1. Both pairs are near origin and destination.
      final o1x = stop('O1X', 50, 20);
      final d1x = stop('D1X', 2050, 20);
      final net = network(
        [o1, o1x, d1, d1x, x2],
        [
          service('20', [
            ['O1', 'X2', 'D1'],
            ['D1X', 'X2', 'O1X'],
          ]),
        ],
      );
      final best = optionsOf(planDirectBus(net, origin, destination)).single;
      expect(best.board.code, 'O1');
      expect(best.alight.code, 'D1');
      expect(best.direction, 0);
    });

    test('destination before origin in the only route → no direct bus', () {
      final net = network(
        [o1, x2, d1],
        [
          service('30', [
            ['D1', 'X2', 'O1'],
          ]),
        ],
      );
      expect(planDirectBus(net, origin, destination), isA<NoDirectBus>());
    });

    test('one-direction service: only the forward journey matches', () {
      final net = network(
        [o1, x2, d1],
        [
          service('31', [
            ['O1', 'X2', 'D1'],
          ]),
        ],
      );
      expect(optionsOf(planDirectBus(net, origin, destination)), hasLength(1));
      expect(planDirectBus(net, destination, origin), isA<NoDirectBus>());
    });
  });

  group('loops and repeated stops (§9.4)', () {
    test('loop: interchange at both ends; boarding mid-loop to the end', () {
      // I is the interchange (first and last). Origin is near Q, destination
      // near I.
      final i = stop('I', 2050, 0);
      final p = stop('P', 1000, 500);
      final q = stop('Q', 50, 0);
      final r = stop('R', 1000, -500);
      final net = network(
        [i, p, q, r],
        [
          service('40', [
            ['I', 'P', 'Q', 'R', 'I'],
          ]),
        ],
      );
      final best = optionsOf(planDirectBus(net, origin, destination)).single;
      expect(best.board.code, 'Q');
      expect(best.alight.code, 'I');
      expect(best.stops, 2); // Q (index 2) → I (index 4)
      expect(best.isLoop, isTrue);
    });

    test('loop: from the interchange, the first occurrence is used', () {
      final i = stop('I', 50, 0);
      final p = stop('P', 1000, 500);
      final q = stop('Q', 2050, 0);
      final net = network(
        [i, p, q],
        [
          service('41', [
            ['I', 'P', 'Q', 'I'],
          ]),
        ],
      );
      final best = optionsOf(planDirectBus(net, origin, destination)).single;
      expect(best.stops, 2); // I (0) → Q (2), never Q → I
    });

    test('origin stop repeated: the shortest valid segment is kept', () {
      final net = network(
        [o1, x1, x2, d1],
        [
          service('50', [
            ['O1', 'X1', 'X2', 'O1', 'D1'],
          ]),
        ],
      );
      expect(
        optionsOf(planDirectBus(net, origin, destination)).single.stops,
        1,
      );
    });

    test('destination stop repeated: the first occurrence after o counts', () {
      final net = network(
        [o1, x1, x2, d1],
        [
          service('51', [
            ['O1', 'D1', 'X1', 'X2', 'D1'],
          ]),
        ],
      );
      expect(
        optionsOf(planDirectBus(net, origin, destination)).single.stops,
        1,
      );
    });

    test('a repeated stop never pairs with itself, or with d before o', () {
      final net = network(
        [o1, x1, d1],
        [
          service('52', [
            ['D1', 'O1', 'X1', 'O1'],
          ]),
        ],
      );
      expect(planDirectBus(net, origin, destination), isA<NoDirectBus>());
    });

    test(
      'same pair in both directions: the direction with fewer stops wins',
      () {
        final net = network(
          [o1, x1, x2, x3, d1],
          [
            service('60', [
              ['O1', 'X1', 'X2', 'X3', 'D1'], // 4 stops
              ['X3', 'O1', 'D1'], // 1 stop
            ]),
          ],
        );
        final best = optionsOf(planDirectBus(net, origin, destination)).single;
        expect(best.direction, 1);
        expect(best.stops, 1);
      },
    );
  });

  group('candidate sets', () {
    test('origin stop == destination stop is skipped', () {
      // One stop S is within 400 m of both points (they are 600 m apart).
      final s = stop('S', 300, 0);
      final far = stop('F', 3000, 3000); // near neither point
      final net = network(
        [s, far],
        [
          service('70', [
            ['S', 'F', 'S'],
          ]),
        ],
      );
      final plan = planDirectBus(net, at(0, 0), at(600, 0));
      expect(plan, isA<NoDirectBus>());
    });

    test('multiple nearby origin and destination stops: the score decides', () {
      // O1 is closer but 3 stops away; O2 is farther but 1 stop away.
      final net = network(
        [o1, o2, x1, x2, d1, d2],
        [
          service('80', [
            ['O1', 'X1', 'X2', 'O2', 'D2', 'D1'],
          ]),
        ],
      );
      final best = optionsOf(planDirectBus(net, origin, destination)).single;
      // O2→D2: 5 + 5 + 1.5 = 11.5; O2→D1: 5 + 1 + 3 = 9; O1→D1: 1 + 1 + 7.5 = 9.5
      expect(best.board.code, 'O2');
      expect(best.alight.code, 'D1');
      expect(best.score, 9);
    });

    test('several services: best per service, ranked by score, top 3 only', () {
      final net = network(
        [o1, o2, x1, x2, x3, d1, d2],
        [
          service('101', [
            ['O1', 'D1'],
          ]), // 1 + 1 + 1.5 = 3.5
          service('102', [
            ['O1', 'X1', 'D1'],
          ]), // 5
          service('103', [
            ['O2', 'X1', 'X2', 'D2'],
          ]), // 5 + 5 + 4.5 = 14.5
          service('104', [
            ['O1', 'X1', 'X2', 'D1'],
            ['O2', 'D2'],
          ]), // best per service: 6.5 (dir 0) vs 11.5 (dir 1)
          service('105', [
            ['O1', 'X1', 'X2', 'X3', 'D1'],
          ]), // 8
        ],
      );
      final options = optionsOf(planDirectBus(net, origin, destination));
      expect(options.map((o) => o.service.number), ['101', '102', '104']);
      expect(options.map((o) => o.score), [3.5, 5, 6.5]);
      expect(options[2].direction, 0); // one entry per service
    });

    test('ties: fewer stops first, then service number in natural order', () {
      final net = network(
        [o1, o2, x1, d1, d2],
        [
          // All score 3.5 + 1.5 = 5 except where noted.
          service('10', [
            ['O1', 'X1', 'D1'],
          ]), // 1 + 1 + 3 = 5, 2 stops
          service('2', [
            ['O1', 'X1', 'D1'],
          ]), // 5, 2 stops
          service('9A', [
            ['O1', 'X1', 'D1'],
          ]), // 5, 2 stops
        ],
      );
      final options = optionsOf(planDirectBus(net, origin, destination));
      expect(options.map((o) => o.service.number), ['2', '9A', '10']);

      // Equal score, fewer stops first (before the service number):
      // A1 = 1 + 1 + 1.5 × 3 = 6.5 (3 stops); B1 = 4 + 1 + 1.5 × 1 = 6.5 (1 stop).
      final o4 = stop('O4', 200, 0); // 200 × 1.3 / 80 = 3.25 → 4 min
      final net2 = network(
        [o1, o4, x1, x2, d1],
        [
          service('A1', [
            ['O1', 'X1', 'X2', 'D1'],
          ]),
          service('B1', [
            ['O4', 'D1'],
          ]),
        ],
      );
      final tied = optionsOf(planDirectBus(net2, origin, destination));
      expect(tied.map((o) => o.score), [6.5, 6.5]);
      expect(tied.map((o) => o.service.number), ['B1', 'A1']);
    });

    test('deterministic: the same input always gives the same order', () {
      final net = network(
        [o1, x1, d1],
        [
          for (final n in ['7', '3', '12', '3A', '1'])
            service(n, [
              ['O1', 'X1', 'D1'],
            ]),
        ],
      );
      final first = optionsOf(planDirectBus(net, origin, destination))
          .map((o) => o.service.number)
          .toList();
      for (var i = 0; i < 5; i++) {
        expect(
          optionsOf(planDirectBus(net, origin, destination))
              .map((o) => o.service.number),
          first,
        );
      }
      expect(first, ['1', '3', '3A']);
    });
  });

  group('radius widening (400 m → 800 m, once)', () {
    test('no stop within 400 m of the origin → widened to 800 m', () {
      final net = network(
        [oFar, x2, d1],
        [
          service('90', [
            ['O3', 'X2', 'D1'],
          ]),
        ],
      );
      final plan = planDirectBus(net, origin, destination) as DirectBusOptions;
      expect(plan.radiusMeters, 800);
      expect(plan.options.single.board.code, 'O3');
    });

    test('stops within 400 m but no direct service → widened to 800 m', () {
      final net = network(
        [o1, oFar, x2, d1],
        [
          service('91', [
            ['O1', 'X2'],
          ]), // reaches neither destination stop
          service('92', [
            ['O3', 'X2', 'D1'],
          ]),
        ],
      );
      final plan = planDirectBus(net, origin, destination) as DirectBusOptions;
      expect(plan.radiusMeters, 800);
      expect(plan.options.single.service.number, '92');
    });

    test('a match within 400 m is not widened', () {
      final net = network(
        [o1, oFar, x2, d1],
        [
          service('93', [
            ['O1', 'X2', 'D1'],
          ]),
          service('94', [
            ['O3', 'D1'],
          ]),
        ],
      );
      final plan = planDirectBus(net, origin, destination) as DirectBusOptions;
      expect(plan.radiusMeters, 400);
      expect(plan.options.map((o) => o.service.number), ['93']);
    });

    test('no stop within 800 m → NoNearbyStops for that side', () {
      final net = network(
        [d1],
        [
          service('95', [
            ['D1'],
          ]),
        ],
      );
      final plan = planDirectBus(net, origin, destination) as NoNearbyStops;
      expect(plan.side, JourneyEnd.origin);
      expect(plan.radiusMeters, 800);

      final plan2 = planDirectBus(
        network([o1], []),
        origin,
        destination,
      ) as NoNearbyStops;
      expect(plan2.side, JourneyEnd.destination);
    });

    test('stops nearby but no direct service even at 800 m → NoDirectBus', () {
      final net = network(
        [o1, d1, x2],
        [
          service('96', [
            ['O1', 'X2'],
          ]),
          service('97', [
            ['X2', 'D1'],
          ]),
        ],
      );
      final plan = planDirectBus(net, origin, destination) as NoDirectBus;
      expect(plan.radiusMeters, 800);
    });

    test('radii and weights are configurable', () {
      final net = network(
        [o2, x2, d1],
        [
          service('98', [
            ['O2', 'X2', 'D1'],
          ]),
        ],
      );
      final plan = planDirectBus(
        net,
        origin,
        destination,
        config: const PlannerConfig(
          stopRadiusMeters: 100,
          widenedStopRadiusMeters: 200,
        ),
      );
      expect(plan, isA<NoNearbyStops>()); // O2 is 250 m away
      final weighted = planDirectBus(
        net,
        origin,
        destination,
        config: const PlannerConfig(stopWeight: 10),
      );
      expect(optionsOf(weighted).single.score, 5 + 1 + 10 * 2);
    });
  });

  test('a stop outside Singapore (e.g. across the Causeway) is not chosen '
      'for a Singapore journey', () {
    final larkin = BusStop(
      code: '46239',
      position: const LatLng(1.49552, 103.74),
      name: 'Larkin Ter',
      road: 'Jln Garuda',
    );
    final net = network(
      [larkin, o1, x2, d1],
      [
        service('160', [
          ['O1', 'X2', 'D1', '46239'],
        ]),
      ],
    );
    final best = optionsOf(planDirectBus(net, origin, destination)).single;
    expect(best.alight.code, 'D1');
  });
}
