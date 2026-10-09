// E2 static journey-time estimate (docs/e2-static-journey-time-implementation-plan.md
// §3, §8 T1): the bus-leg model, its validity guard and the rounding order.
// Pure Dart (no widget, no integration_test fake), so CI also runs it on
// Chrome. Golden values come from the app's own haversineMeters (plan §3.4).
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/core/config/app_config.dart';
import 'package:sg_smart_commute/core/geo/geo.dart';
import 'package:sg_smart_commute/features/journey/domain/bus_network.dart';
import 'package:sg_smart_commute/features/journey/domain/direct_bus_planner.dart';
import 'package:sg_smart_commute/features/journey/domain/journey_estimate.dart';
import 'package:sg_smart_commute/features/journey/domain/walking.dart';

BusStop stop(String code, double lat, double lng) => BusStop(
  code: code,
  position: LatLng(lat, lng),
  name: code,
  road: 'Test Rd',
);

BusService service(String number, List<List<String>> directions) =>
    BusService(number: number, name: 'Test $number', directions: directions);

BusNetwork networkOf(
  List<BusStop> stops, [
  List<BusService> services = const [],
]) => BusNetwork(
  stops: {for (final s in stops) s.code: s},
  services: {for (final s in services) s.number: s},
);

/// Stop k at (1.30 + 0.01·k, 103.80): one hop is 1,111.9492664 m.
final meridianStops = [
  for (var k = 0; k <= 90; k++) stop('M$k', 1.30 + k * 0.01, 103.80),
];
final meridianCodes = [for (final s in meridianStops) s.code];
final meridian = networkOf(meridianStops);
final meridianService = service('M', [meridianCodes]);

double? meridianRide(int stops, {int from = 0}) => estimateBusMinutes(
  meridian,
  service: meridianService,
  direction: 0,
  boardIndex: from,
  stopCount: stops,
);

/// A point [meters] north of [p] (one degree of latitude = 111,194.9266 m).
LatLng north(LatLng p, double meters) =>
    LatLng(p.latitude + meters / 111194.92664455883, p.longitude);

/// A direct option on [s] (direction 0) from [boardIndex], with walks from
/// [walkToMeters] north of the boarding stop and to [walkFromMeters] north
/// of the alighting stop.
BusOption optionOn(
  BusNetwork network,
  BusService s, {
  required int boardIndex,
  required int stops,
  double walkToMeters = 0,
  double walkFromMeters = 0,
  String? boardCode,
  String? alightCode,
}) {
  final codes = s.directions.first;
  final board = network.stops[boardCode ?? codes[boardIndex]]!;
  final alight = network.stops[alightCode ?? codes[boardIndex + stops]]!;
  return BusOption(
    service: s,
    direction: 0,
    board: board,
    boardIndex: boardIndex,
    alight: alight,
    stops: stops,
    walkToStop: WalkEstimate.between(
      north(board.position, walkToMeters),
      board.position,
    ),
    walkFromStop: WalkEstimate.between(
      alight.position,
      north(alight.position, walkFromMeters),
    ),
    score: 0,
    towardName: codes.last,
    isLoop: false,
  );
}

void main() {
  test('the frozen constants', () {
    expect(JourneyConfig.busMinutesPerKm, 2.85);
    expect(JourneyConfig.busMinutesPerStop, 0.35);
    expect(JourneyConfig.busEstimateMaxMinutes, 300);
    expect(JourneyConfig.estimateRoundingMinutes, 5);
  });

  group('bus leg: distance and stop count (T1.1)', () {
    for (final (stops, exact, shown) in [
      (1, 3.519055409369927, 4),
      (3, 10.557166228109779, 11),
      (10, 35.19055409369927, 36),
      (35, 123.16693932794745, 124),
    ]) {
      test('$stops stops along a meridian', () {
        final minutes = meridianRide(stops)!;
        expect(minutes, closeTo(exact, 1e-9));
        expect(rideMinutesShown(minutes), shown);
      });
    }
  });

  test('a later boarding occurrence sums only its own stops (T1.2)', () {
    expect(meridianRide(3, from: 5), closeTo(10.557166228109779, 1e-9));
    // Uneven hops: 0.01, 0.02, 0.03 and 0.04 degrees of latitude.
    final uneven = networkOf([
      stop('K0', 1.30, 103.80),
      stop('K1', 1.31, 103.80),
      stop('K2', 1.33, 103.80),
      stop('K3', 1.36, 103.80),
      stop('K4', 1.40, 103.80),
    ]);
    final s = service('K', [
      ['K0', 'K1', 'K2', 'K3', 'K4'],
    ]);
    double? ride(int from) => estimateBusMinutes(
      uneven,
      service: s,
      direction: 0,
      boardIndex: from,
      stopCount: 2,
    );
    expect(ride(2), closeTo(22.883387865589416, 1e-9));
    expect(ride(0), closeTo(10.207166228109779, 1e-9));
  });

  test('the distance is the sum of the hops, not the straight line (T1.3)', () {
    final u = networkOf([
      stop('A', 1.30, 103.80),
      stop('B', 1.31, 103.80),
      stop('C', 1.31, 103.81),
      stop('D', 1.30, 103.81),
    ]);
    final minutes = estimateBusMinutes(
      u,
      service: service('U', [
        ['A', 'B', 'C', 'D'],
      ]),
      direction: 0,
      boardIndex: 0,
      stopCount: 3,
    );
    expect(minutes, closeTo(10.55633794606955, 1e-9)); // straight A-D: 4.2182
  });

  test('a loop with a repeated stop uses the boarding occurrence (T1.4)', () {
    final loop = networkOf([
      stop('L0', 1.30, 103.80),
      stop('L1', 1.31, 103.80),
      stop('L2', 1.32, 103.80),
      stop('L3', 1.31, 103.81),
    ]);
    final s = service('L', [
      ['L0', 'L1', 'L2', 'L1', 'L3', 'L0'],
    ]);
    // L1 is at 1 and 3; the planner boards at 3 for L1 -> L3 (one stop).
    expect(
      estimateBusMinutes(
        loop,
        service: s,
        direction: 0,
        boardIndex: 3,
        stopCount: 1,
      ),
      closeTo(3.5182271273296966, 1e-9),
    );
  });

  test('both coefficients count: same km, different stops (T1.5)', () {
    // Ten 0.001-degree hops cover the same km as one meridian hop.
    final dense = networkOf([
      for (var j = 0; j <= 10; j++) stop('D$j', 1.30 + j * 0.001, 103.80),
    ]);
    final minutes = estimateBusMinutes(
      dense,
      service: service('D', [
        [for (var j = 0; j <= 10; j++) 'D$j'],
      ]),
      direction: 0,
      boardIndex: 0,
      stopCount: 10,
    );
    expect(minutes, closeTo(6.669055409369927, 1e-9));
    expect(minutes! - meridianRide(1)!, closeTo(0.35 * 9, 1e-9));
  });

  test('the same stop pair on two services gives two estimates (T1.6)', () {
    final pair = networkOf([
      stop('A', 1.30, 103.80),
      stop('B', 1.31, 103.80),
      stop('C', 1.305, 103.81),
    ]);
    double? ride(List<String> codes) => estimateBusMinutes(
      pair,
      service: service('S', [codes]),
      direction: 0,
      boardIndex: 0,
      stopCount: codes.length - 1,
    );
    expect(ride(['A', 'B']), closeTo(3.519055409369927, 1e-9));
    expect(ride(['A', 'C', 'B']), closeTo(7.784752963238632, 1e-9));
  });

  group('no estimate: omitted, never clamped (T1.7)', () {
    double? ride(
      BusNetwork network,
      BusService s, {
      int direction = 0,
      int boardIndex = 0,
      int stopCount = 1,
      double minutesPerKm = JourneyConfig.busMinutesPerKm,
      double minutesPerStop = JourneyConfig.busMinutesPerStop,
    }) => estimateBusMinutes(
      network,
      service: s,
      direction: direction,
      boardIndex: boardIndex,
      stopCount: stopCount,
      minutesPerKm: minutesPerKm,
      minutesPerStop: minutesPerStop,
    );

    test('no stop travelled', () {
      expect(ride(meridian, meridianService, stopCount: 0), isNull);
      expect(ride(meridian, meridianService, stopCount: -1), isNull);
    });

    test('indices outside the direction', () {
      expect(ride(meridian, meridianService, boardIndex: -1), isNull);
      expect(
        ride(meridian, meridianService, boardIndex: 90, stopCount: 1),
        isNull,
      );
      expect(ride(meridian, meridianService, direction: 1), isNull);
      expect(ride(meridian, meridianService, direction: -1), isNull);
    });

    test('a ride stop missing from the network; other stops do not matter', () {
      final s = service('G', [
        ['GHOST', 'M0', 'M1'],
      ]);
      expect(ride(meridian, s, boardIndex: 0), isNull);
      expect(
        ride(meridian, s, boardIndex: 1),
        closeTo(3.519055409369927, 1e-9),
      );
    });

    test('a non-finite coordinate', () {
      final bad = networkOf([
        stop('A', 1.30, 103.80),
        stop('N', double.nan, 103.80),
      ]);
      expect(
        ride(
          bad,
          service('N', [
            ['A', 'N'],
          ]),
        ),
        isNull,
      );
      expect(
        ride(meridian, meridianService, minutesPerKm: double.infinity),
        isNull,
      );
    });

    test('a negative result', () {
      expect(ride(meridian, meridianService, minutesPerKm: -1000), isNull);
    });

    test('over 300 minutes: none, not 300', () {
      final under = meridianRide(85)!;
      expect(under, closeTo(299.1197097964438, 1e-9));
      expect(rideMinutesShown(under), 300);
      expect(meridianRide(86), isNull); // about 302.6
    });

    test('a ride may end at the last stop of its direction', () {
      expect(
        ride(meridian, meridianService, boardIndex: 89, stopCount: 1),
        closeTo(3.519055409369927, 1e-6),
      );
      expect(
        ride(meridian, meridianService, boardIndex: 88, stopCount: 2),
        closeTo(7.03811081873985, 1e-6),
      );
    });

    test('exactly 300 minutes is valid', () {
      expect(
        ride(meridian, meridianService, minutesPerKm: 0, minutesPerStop: 300),
        300,
      );
      expect(
        ride(
          meridian,
          meridianService,
          minutesPerKm: 0,
          minutesPerStop: 300.0001,
        ),
        isNull,
      );
    });
  });

  group('a direct option (T1.8)', () {
    test('the parts are the displayed walks plus the rounded-up ride', () {
      final o = optionOn(
        meridian,
        meridianService,
        boardIndex: 2,
        stops: 3,
        walkToMeters: 100, // ~2 min walk
        walkFromMeters: 300, // ~5 min walk
      );
      expect(o.walkToStop.minutes, 2);
      expect(o.walkFromStop.minutes, 5);
      final e = estimateDirectJourney(o, meridian)!;
      expect(e.walkToStopMinutes, 2);
      expect(e.rideMinutes, 11); // 10.557
      expect(e.walkFromStopMinutes, 5);
      expect(e.partsMinutes, 18);
      expect(e.shownMinutes, 20);
    });

    test('each part changes the total', () {
      int parts({double to = 0, double from = 0, int stops = 3}) =>
          estimateDirectJourney(
            optionOn(
              meridian,
              meridianService,
              boardIndex: 0,
              stops: stops,
              walkToMeters: to,
              walkFromMeters: from,
            ),
            meridian,
          )!.partsMinutes;
      final base = parts();
      expect(base, 11);
      expect(parts(to: 100), base + 2);
      expect(parts(from: 300), base + 5);
      expect(parts(stops: 10), 36);
    });

    test('a direction or alighting index outside the service: none', () {
      final o = optionOn(meridian, meridianService, boardIndex: 0, stops: 3);
      BusOption copy({int? direction, int? stops}) => BusOption(
        service: o.service,
        direction: direction ?? o.direction,
        board: o.board,
        boardIndex: o.boardIndex,
        alight: o.alight,
        stops: stops ?? o.stops,
        walkToStop: o.walkToStop,
        walkFromStop: o.walkFromStop,
        score: o.score,
        towardName: o.towardName,
        isLoop: o.isLoop,
      );
      expect(estimateDirectJourney(copy(direction: 1), meridian), isNull);
      expect(estimateDirectJourney(copy(direction: -1), meridian), isNull);
      expect(estimateDirectJourney(copy(stops: 91), meridian), isNull);
    });

    test('board or alight codes that disagree with the network: none', () {
      expect(
        estimateDirectJourney(
          optionOn(
            meridian,
            meridianService,
            boardIndex: 0,
            stops: 3,
            boardCode: 'M1',
          ),
          meridian,
        ),
        isNull,
      );
      expect(
        estimateDirectJourney(
          optionOn(
            meridian,
            meridianService,
            boardIndex: 0,
            stops: 3,
            alightCode: 'M4',
          ),
          meridian,
        ),
        isNull,
      );
    });
  });

  group('rounding (T1.9; plan §3.2, §3.3)', () {
    test('up to a multiple of 5', () {
      for (final (minutes, rounded) in [
        (4, 5),
        (25, 25),
        (26, 30),
        (29, 30),
        (30, 30),
        (31, 35),
        (147, 150),
        (300, 300),
      ]) {
        expect(roundUpToMultiple(minutes, 5), rounded, reason: '$minutes');
      }
    });

    test('the threshold cases, with integer walks', () {
      for (final (walkTo, exact, walkFrom, ride, parts, shown) in [
        (2, 22.0, 1, 22, 25, 25),
        (2, 22.0000001, 1, 23, 26, 30),
        (2, 21.9999999, 1, 22, 25, 25),
        (2, 21.5, 1, 22, 25, 25),
        (3, 20.0, 2, 20, 25, 25),
        (3, 20.01, 2, 21, 26, 30),
        (1, 27.6, 1, 28, 30, 30),
        (1, 28.01, 1, 29, 31, 35),
        (0, 3.5190554, 0, 4, 4, 5),
        (13, 120.9, 13, 121, 147, 150),
        (0, 300.0, 0, 300, 300, 300),
      ]) {
        final e = DirectJourneyEstimate(
          walkToStopMinutes: walkTo,
          rideMinutes: rideMinutesShown(exact),
          walkFromStopMinutes: walkFrom,
        );
        final reason = '$walkTo + $exact + $walkFrom';
        expect(e.rideMinutes, ride, reason: reason);
        expect(e.partsMinutes, parts, reason: reason);
        expect(e.shownMinutes, shown, reason: reason);
      }
    });

    test('the total is the smallest multiple of 5 at or above the shown '
        'parts, and equals the exact sum rounded up to 5', () {
      const fractions = [-1e-9, 0.0, 1e-9, 0.01, 0.49, 0.5, 0.51, 0.99];
      var cases = 0;
      for (var walkTo = 0; walkTo <= 13; walkTo++) {
        for (var walkFrom = 0; walkFrom <= 13; walkFrom++) {
          for (var k = 1; k <= 300; k++) {
            for (final f in fractions) {
              final exact = k + f;
              final e = DirectJourneyEstimate(
                walkToStopMinutes: walkTo,
                rideMinutes: rideMinutesShown(exact),
                walkFromStopMinutes: walkFrom,
              );
              final shown = e.shownMinutes;
              final parts = e.partsMinutes;
              if (shown % 5 != 0 ||
                  shown < parts ||
                  shown >= parts + 5 ||
                  shown != ((walkTo + exact + walkFrom) / 5).ceil() * 5) {
                fail(
                  '$walkTo + $exact + $walkFrom: parts $parts, shown $shown',
                );
              }
              cases++;
            }
          }
        }
      }
      expect(cases, 470400);
    });
  });
}
