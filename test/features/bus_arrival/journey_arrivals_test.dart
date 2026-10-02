// journeyArrivalsProvider state (guide v2.1 §9.2 step 7, §10, §15): arrivals
// only for the displayed plan, one request per boarding stop, stale answers
// never attached to a newer journey, failures kept per stop, Retry, and
// refresh without recomputing the static plan.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/core/errors/app_failure.dart';
import 'package:sg_smart_commute/core/geo/geo.dart';
import 'package:sg_smart_commute/core/time/clock.dart';
import 'package:sg_smart_commute/features/bus_arrival/bus_arrival_providers.dart';
import 'package:sg_smart_commute/features/bus_arrival/domain/bus_arrival.dart';
import 'package:sg_smart_commute/features/journey/domain/direct_bus_planner.dart';
import 'package:sg_smart_commute/features/journey/journey_providers.dart';
import 'package:sg_smart_commute/main.dart' show noAutomaticRetry;

import '../../fakes/fake_bus_arrival_repository.dart';
import '../../fakes/fake_bus_network.dart';
import '../../fakes/fake_environment_repository.dart';
import '../../fakes/fake_place_search_repository.dart';

const bishan = LatLng(1.3508, 103.8485);

/// Bishan → VivoCity: F20 @ BSH2, F10 @ BSH1, F30 @ BSH1.
final toVivo = planDirectBus(
  fakeBusNetwork(),
  bishan,
  vivoCity.position,
) as DirectBusOptions;

/// Bishan → ION Orchard: F30 @ BSH1 only.
final toIon = planDirectBus(
  fakeBusNetwork(),
  bishan,
  ionOrchard.position,
) as DirectBusOptions;

class _PlanHolder extends Notifier<JourneyPlan?> {
  @override
  JourneyPlan? build() => null;
  void set(JourneyPlan? plan) => state = plan;
}

final _planHolder = NotifierProvider<_PlanHolder, JourneyPlan?>(
  _PlanHolder.new,
);

void main() {
  late FakeBusArrivalRepository arrivals;
  late DateTime now;
  late int planBuilds;
  late ProviderContainer c;

  setUp(() {
    arrivals = FakeBusArrivalRepository();
    now = fakeNow;
    planBuilds = 0;
    c = ProviderContainer(
      retry: noAutomaticRetry,
      overrides: [
        journeyPlanProvider.overrideWith((ref) async {
          planBuilds++;
          return ref.watch(_planHolder);
        }),
        busArrivalRepositoryProvider.overrideWithValue(arrivals),
        clockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(c.dispose);
    // Keep the provider alive between reads, as a mounted widget would.
    final sub = c.listen(journeyArrivalsProvider, (_, _) {});
    addTearDown(sub.close);
  });

  Future<JourneyArrivals?> settle() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    return c.read(journeyArrivalsProvider).value;
  }

  test('no plan, or no displayed bus option → nothing is requested', () async {
    expect(await settle(), isNull);
    c.read(_planHolder.notifier).set(const NoDirectBus(radiusMeters: 800));
    expect(await settle(), isNull);
    expect(arrivals.totalCalls, 0);
  });

  test(
    'one request per distinct boarding stop: F10 and F30 share BSH1',
    () async {
      c.read(_planHolder.notifier).set(toVivo);
      final result = (await settle())!;
      expect(identical(result.plan, toVivo), isTrue);
      expect(arrivals.calls, {'BSH2': 1, 'BSH1': 1});
      final bsh1 = result.byStop['BSH1']! as StopArrivalsLoaded;
      expect(nextArrivals(bsh1.arrivals, 'F10', now: now), hasLength(2));
      expect(nextArrivals(bsh1.arrivals, 'F30', now: now), hasLength(1));
      expect(result.checkedAt, now);
    },
  );

  test("journey A's late answer cannot populate journey B", () async {
    arrivals.hold('BSH2');
    c.read(_planHolder.notifier).set(toVivo); // A: BSH2 + BSH1
    await settle();
    expect(c.read(journeyArrivalsProvider).value, isNull); // A still pending

    c.read(_planHolder.notifier).set(toIon); // B: BSH1 only
    final b = (await settle())!;
    expect(identical(b.plan, toIon), isTrue);

    arrivals.release('BSH2'); // A's answer arrives after B
    final after = (await settle())!;
    expect(identical(after.plan, toIon), isTrue);
    expect(after.byStop.keys, ['BSH1']);
  });

  test('changing the journey replaces the arrivals: the previous plan\'s '
      'are never reported for the new one', () async {
    c.read(_planHolder.notifier).set(toVivo);
    final a = (await settle())!;
    c.read(_planHolder.notifier).set(toIon);
    // While B loads, any value still visible belongs to A, and says so.
    final during = c.read(journeyArrivalsProvider).value;
    expect(during == null || identical(during.plan, toVivo), isTrue);
    final b = (await settle())!;
    expect(identical(b.plan, toIon), isTrue);
    expect(identical(a.plan, b.plan), isFalse);
  });

  test(
    'a failed stop is kept per stop and leaves the static plan intact',
    () async {
      arrivals.failures['BSH2'] = const NetworkUnavailable();
      c.read(_planHolder.notifier).set(toVivo);
      final result = (await settle())!;
      expect(result.byStop['BSH2'], isA<StopArrivalsFailed>());
      expect(
        (result.byStop['BSH2']! as StopArrivalsFailed).failure,
        isA<NetworkUnavailable>(),
      );
      expect(result.byStop['BSH1'], isA<StopArrivalsLoaded>());
      expect(c.read(journeyPlanProvider).value, same(toVivo));
    },
  );

  test('Retry recovers after a failure, without re-requesting a stop still '
      'inside its cache TTL or recomputing the plan', () async {
    arrivals.failures['BSH2'] = const BusArrivalUnavailable();
    c.read(_planHolder.notifier).set(toVivo);
    await settle();
    final builds = planBuilds;

    arrivals.failures.clear();
    c.invalidate(journeyArrivalsProvider); // Retry / Refresh
    final result = (await settle())!;
    expect(result.byStop['BSH2'], isA<StopArrivalsLoaded>());
    expect(arrivals.calls, {'BSH2': 2, 'BSH1': 1}); // failures not cached
    expect(planBuilds, builds, reason: 'Retry must not recompute the plan');
  });

  test('refresh within the TTL makes no request but re-counts ETAs from the '
      'new check time; after the TTL it fetches again', () async {
    c.read(_planHolder.notifier).set(toVivo);
    final first = (await settle())!;
    final builds = planBuilds;

    now = now.add(const Duration(seconds: 10));
    c.invalidate(journeyArrivalsProvider);
    final second = (await settle())!;
    expect(arrivals.totalCalls, 2);
    expect(second.checkedAt, now);
    expect(second.checkedAt.isAfter(first.checkedAt), isTrue);

    now = now.add(const Duration(seconds: 10)); // 20 s after the first fetch
    c.invalidate(journeyArrivalsProvider);
    await settle();
    expect(arrivals.calls, {'BSH2': 2, 'BSH1': 2});
    expect(planBuilds, builds, reason: 'refresh must not recompute the plan');
  });

  test('concurrent refreshes share in-flight requests', () async {
    arrivals.hold('BSH2');
    arrivals.hold('BSH1');
    c.read(_planHolder.notifier).set(toVivo);
    await settle();
    c.invalidate(journeyArrivalsProvider);
    await settle();
    c.invalidate(journeyArrivalsProvider);
    await settle();
    arrivals
      ..release('BSH2')
      ..release('BSH1');
    final result = (await settle())!;
    expect(identical(result.plan, toVivo), isTrue);
    expect(arrivals.calls, {'BSH2': 1, 'BSH1': 1});
  });

  test('arrivalsFor: only the arrivals fetched for that exact plan', () async {
    c.read(_planHolder.notifier).set(toVivo);
    await settle();
    final async = c.read(journeyArrivalsProvider);
    expect(identical(async.arrivalsFor(toVivo)?.plan, toVivo), isTrue);
    expect(async.arrivalsFor(toIon), isNull);
    expect(
      const AsyncValue<JourneyArrivals?>.loading().arrivalsFor(toVivo),
      isNull,
    );
  });

  test('boardsAtLoopTerminal: only a loop boarded at its first stop', () {
    final f20 = toVivo.options.first;
    expect(f20.isLoop, isFalse);
    expect(boardsAtLoopTerminal(f20), isFalse);
  });
}
