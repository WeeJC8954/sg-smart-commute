// Service matching and ETA formatting (guide v2.1 §10, §18).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/core/config/app_config.dart';
import 'package:sg_smart_commute/features/bus_arrival/data/arrivelah_parser.dart';
import 'package:sg_smart_commute/features/bus_arrival/domain/bus_arrival.dart';

final t0 = DateTime.utc(2026, 10, 2, 3);

BusArrival at(String no, Duration? after, {int? visit}) => BusArrival(
  serviceNo: no,
  busStopCode: '1',
  estimatedArrival: after == null ? null : t0.add(after),
  visitNumber: visit,
  source: 'test',
);

StopArrivals stop(List<ServiceArrivals> services) =>
    StopArrivals(services: services);

ServiceArrivals svc(String no, List<BusArrival> arrivals) =>
    ServiceArrivals(serviceNo: no, arrivals: arrivals);

void main() {
  group('nextArrivals: service-number matching', () {
    final s = stop([
      svc('10', [at('10', const Duration(minutes: 5))]),
      svc('100', [at('100', const Duration(minutes: 1))]),
      svc('196A', [at('196A', const Duration(minutes: 2))]),
      svc('960e', [at('960e', const Duration(minutes: 3))]),
    ]);

    test('exact number only: "10" is not "100", "196" is not "196A"', () {
      expect(nextArrivals(s, '10', now: t0).single.serviceNo, '10');
      expect(nextArrivals(s, '100', now: t0).single.serviceNo, '100');
      expect(nextArrivals(s, '196', now: t0), isEmpty);
      expect(nextArrivals(s, '196A', now: t0).single.serviceNo, '196A');
    });

    test('ignores surrounding spaces and letter case', () {
      expect(nextArrivals(s, ' 196a ', now: t0), hasLength(1));
      expect(nextArrivals(s, '960E', now: t0), hasLength(1));
    });

    test('a service the stop does not list → empty ("no live arrival"), '
        'which is not a verdict on the route', () {
      expect(nextArrivals(s, '65', now: t0), isEmpty);
      expect(nextArrivals(stop(const []), '10', now: t0), isEmpty);
    });
  });

  group('nextArrivals: selection', () {
    test('soonest first, at most three, only arrivals with a time', () {
      final s = stop([
        svc('10', [
          at('10', const Duration(minutes: 9)),
          at('10', null),
          at('10', const Duration(minutes: 2)),
        ]),
        // A second entry for the same number (seen in ArriveLah's README).
        svc('10', [
          at('10', const Duration(minutes: 20)),
          at('10', const Duration(minutes: 5)),
        ]),
      ]);
      expect(nextArrivals(s, '10', now: t0).map((a) => a.estimatedArrival), [
        t0.add(const Duration(minutes: 2)),
        t0.add(const Duration(minutes: 5)),
        t0.add(const Duration(minutes: 9)),
      ]);
    });

    test('implausible times are dropped: a replayed past bus never pushes '
        'out a real one, and a far-future time is never shown', () {
      final s = stop([
        svc('10', [
          at('10', const Duration(days: -2)), // an old body, replayed
          at('10', const Duration(minutes: -3)), // left 3 min ago
          at('10', const Duration(minutes: 4)),
          at('10', const Duration(minutes: 9)),
          at('10', const Duration(minutes: 15)),
          at('10', const Duration(hours: 4)), // bogus
        ]),
      ]);
      expect(nextArrivals(s, '10', now: t0).map((a) => a.estimatedArrival), [
        t0.add(const Duration(minutes: 4)),
        t0.add(const Duration(minutes: 9)),
        t0.add(const Duration(minutes: 15)),
      ]);
    });

    test('only implausible times → empty ("no live arrival"), never "Arr"', () {
      final s = stop([
        svc('10', [
          at('10', const Duration(minutes: -30)),
          at('10', const Duration(hours: 5)),
        ]),
      ]);
      expect(nextArrivals(s, '10', now: t0), isEmpty);
    });

    test('ArriveLah body with a stale and a year-9999 time → only the real '
        'bus', () {
      final parsed = parseArriveLah({
        'services': [
          {
            'no': '57',
            'next': {'time': '2026-09-30T08:00:00+08:00'},
            'next2': {'time': '2026-10-02T11:06:00+08:00'},
            'next3': {'time': '9999-01-01T00:00:00+08:00'},
          },
        ],
      }, '03019');
      // The parser keeps well-formed times as data; the bounds apply when
      // the arrivals are selected for display.
      expect(parsed.services.single.arrivals, hasLength(3));
      expect(
        nextArrivals(parsed, '57', now: t0).single.estimatedArrival,
        DateTime.utc(2026, 10, 2, 3, 6),
      );
    });

    test('every slot without a time → empty, never "0 min"', () {
      final s = stop([
        svc('10', [at('10', null), at('10', null)]),
      ]);
      expect(nextArrivals(s, '10', now: t0), isEmpty);
    });

    test('boarding a loop where it starts and ends: visit-2 buses (ending '
        'the loop) are left out', () {
      final s = stop([
        svc('291', [
          at('291', const Duration(minutes: 1), visit: 2),
          at('291', const Duration(minutes: 3), visit: 2),
          at('291', const Duration(minutes: 5), visit: 1),
        ]),
      ]);
      expect(nextArrivals(s, '291', now: t0), hasLength(3));
      expect(
        nextArrivals(
          s,
          '291',
          now: t0,
          boardsAtLoopTerminal: true,
        ).single.visitNumber,
        1,
      );
    });

    test('real fixture: loop 291 at Tampines Int (75009) → one departure', () {
      final real = parseArriveLah(
        jsonDecode(
          File('test/fixtures/arrivelah/stop_75009_loop.json')
              .readAsStringSync(),
        ),
        '75009',
      );
      final departures = nextArrivals(
        real,
        '291',
        now: t0,
        boardsAtLoopTerminal: true,
      );
      expect(
        departures.single.estimatedArrival,
        DateTime.utc(2026, 10, 2, 3, 5),
      );
    });
  });

  group('etaLabel: "Arr" boundary and minute rounding', () {
    String label(Duration d) => etaLabel(t0.add(d), t0);

    test('at most one minute away, or already past → "Arr"', () {
      expect(label(Duration.zero), 'Arr');
      expect(label(const Duration(seconds: 59)), 'Arr');
      expect(label(const Duration(seconds: 60)), 'Arr');
      expect(label(const Duration(seconds: -10)), 'Arr');
      expect(label(const Duration(minutes: -3)), 'Arr');
    });

    test('beyond one minute → whole minutes, rounded down', () {
      expect(label(const Duration(seconds: 61)), '1 min');
      expect(label(const Duration(seconds: 119)), '1 min');
      expect(label(const Duration(seconds: 120)), '2 min');
      expect(label(const Duration(minutes: 7, seconds: 59)), '7 min');
      expect(label(const Duration(minutes: 45)), '45 min');
    });

    test('uses the actual timestamps, whatever their offsets were', () {
      final eta = DateTime.parse('2026-10-02T11:07:30+08:00').toUtc();
      expect(etaLabel(eta, DateTime.utc(2026, 10, 2, 3)), '7 min');
    });
  });

  group('isPlausibleEta: both edges', () {
    bool ok(Duration d) => isPlausibleEta(t0.add(d), t0);

    test('up to maxPastEta ago is kept (shown as "Arr"), beyond is not', () {
      expect(BusArrivalConfig.maxPastEta, const Duration(minutes: 2));
      expect(ok(Duration.zero), isTrue);
      expect(ok(const Duration(minutes: -2)), isTrue);
      expect(ok(const Duration(minutes: -2, seconds: -1)), isFalse);
    });

    test('up to maxFutureEta ahead is kept, beyond is not', () {
      expect(BusArrivalConfig.maxFutureEta, const Duration(hours: 3));
      expect(ok(const Duration(hours: 3)), isTrue);
      expect(ok(const Duration(hours: 3, seconds: 1)), isFalse);
    });
  });

  group('etaSpoken: from the duration, matching etaLabel', () {
    String spoken(Duration d) => etaSpoken(t0.add(d), t0);

    test('"arriving now" exactly where the label is "Arr"', () {
      expect(spoken(const Duration(seconds: 60)), 'arriving now');
      expect(spoken(const Duration(minutes: -3)), 'arriving now');
    });

    test('whole minutes, singular for one', () {
      expect(spoken(const Duration(seconds: 61)), '1 minute');
      expect(spoken(const Duration(seconds: 120)), '2 minutes');
      expect(spoken(const Duration(minutes: 7, seconds: 59)), '7 minutes');
    });

    test('agrees with etaLabel on every second of the first ten minutes', () {
      for (var s = -120; s <= 600; s++) {
        final d = Duration(seconds: s);
        final minutes = minutesUntil(t0.add(d), t0);
        expect(
          etaLabel(t0.add(d), t0),
          minutes == null ? 'Arr' : '$minutes min',
        );
        expect(
          spoken(d).startsWith(minutes == null ? 'arriving' : '$minutes '),
          isTrue,
        );
      }
    });
  });
}
