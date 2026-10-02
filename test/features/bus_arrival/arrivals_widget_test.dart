// Milestone 4 widget tests: live arrivals in the journey card (guide v2.1
// §10, §18). Everything external is a fake (test/fakes/); the clock is
// injected, so every ETA below is exact.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/core/errors/app_failure.dart';
import 'package:sg_smart_commute/core/geo/geo.dart';
import 'package:sg_smart_commute/core/location/location_service.dart';
import 'package:sg_smart_commute/features/bus_arrival/domain/bus_arrival.dart';
import 'package:sg_smart_commute/features/bus_arrival/presentation/option_arrivals.dart';

import '../../fakes/fake_bus_arrival_repository.dart';
import '../../fakes/fake_bus_network.dart';
import '../../fakes/fake_environment_repository.dart';
import '../../fakes/fake_location_service.dart';
import '../../fakes/fake_place_search_repository.dart';
import '../../fakes/test_app.dart';

/// The fake GPS fix (as in the journey widget tests).
const bishanGps = LatLng(1.3508, 103.8485);
const destinationField = Key('destination-field');
const f20 = 'arrivals-BSH2-F20';
const f10 = 'arrivals-BSH1-F10';
const f30 = 'arrivals-BSH1-F30';

Future<void> pumpApp(WidgetTester tester, Widget app) async {
  tester.view.physicalSize = const Size(1080, 5000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
  await tester.pump();
}

Future<void> pick(WidgetTester tester, String query, String result) async {
  await tester.enterText(find.byKey(destinationField), query);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
  await tester.tap(find.text(result));
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

Finder inKey(String key, String text) =>
    find.descendant(of: find.byKey(Key(key)), matching: find.text(text));

Finder inKeyContaining(String key, String text) => find.descendant(
  of: find.byKey(Key(key)),
  matching: find.textContaining(text),
);

void main() {
  late FakeBusArrivalRepository arrivals;
  late FakeBusNetworkRepository bus;
  late DateTime now;

  setUp(() {
    arrivals = FakeBusArrivalRepository();
    bus = FakeBusNetworkRepository();
    now = fakeNow;
  });

  Widget app() => buildTestApp(
    location: FakeLocationService(
      access: LocationAccess.granted,
      position: bishanGps,
    ),
    environment: FakeEnvironmentRepository(),
    places: FakePlaceSearchRepository(),
    busNetwork: bus,
    mrt: fakeMrtRepository(),
    busArrivals: arrivals,
    clock: () => now,
  );

  testWidgets('loading → three ETAs per option, with "Arr", minutes and the '
      'next bus\'s details', (tester) async {
    arrivals
      ..hold('BSH2')
      ..hold('BSH1');
    await pumpApp(tester, app());
    await pick(tester, 'VivoCity', 'VIVOCITY');

    // The static route is already there while arrivals load.
    expect(
      inKey('journey-suggested', 'Take Bus F20 toward VivoCity (fake)'),
      findsOneWidget,
    );
    expect(inKey(f20, OptionArrivals.checking), findsOneWidget);

    arrivals
      ..release('BSH2')
      ..release('BSH1');
    await tester.pump();
    await tester.pump();

    expect(inKey(f20, 'Next buses: Arr · 7 min · 19 min'), findsOneWidget);
    expect(
      inKey(
        f20,
        'Next bus: Seats available · Wheelchair accessible · '
        'Double deck',
      ),
      findsOneWidget,
    );
    // Schedule-based estimates are labelled.
    expect(
      inKey(f10, 'Next buses: 4 min · 12 min (scheduled)'),
      findsOneWidget,
    );
    // Only what the provider sent: no wheelchair claim when it is not marked.
    expect(inKey(f30, 'Next buses: 2 min'), findsOneWidget);
    expect(
      inKey(f30, 'Next bus: Limited standing · Single deck'),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('arrivals-footer')).evaluate().single.widget,
      isA<Text>().having(
        (t) => t.data,
        'data',
        'Arrivals: ArriveLah (LTA DataMall) · checked 12:12 SGT',
      ),
    );
    // F10 and F30 board at BSH1: one request serves both.
    expect(arrivals.calls, {'BSH2': 1, 'BSH1': 1});
  });

  testWidgets('screen readers hear the ETAs in words', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpApp(tester, app());
    await pick(tester, 'VivoCity', 'VIVOCITY');
    // The journey card is read as one merged node.
    final label = tester
        .getSemantics(find.byKey(const Key('journey-card')))
        .label;
    expect(label, contains('Next buses: arriving now, 7 minutes, 19 minutes'));
    expect(label, contains('Next buses: 4 minutes, 12 minutes, scheduled'));
    expect(label, isNot(contains('Arr ·')));
    semantics.dispose();
  });

  testWidgets('service not listed at its stop → "No live arrival available"; '
      'the route stays', (tester) async {
    arrivals.stops = {
      ...fakeStopArrivals(),
      'BSH2': const StopArrivals(busStopCode: 'BSH2', services: []),
    };
    await pumpApp(tester, app());
    await pick(tester, 'VivoCity', 'VIVOCITY');
    expect(inKey(f20, OptionArrivals.noArrival), findsOneWidget);
    expect(
      inKey('journey-suggested', 'Take Bus F20 toward VivoCity (fake)'),
      findsOneWidget,
    );
    expect(find.textContaining('0 min'), findsNothing);
    expect(
      inKey(f10, 'Next buses: 4 min · 12 min (scheduled)'),
      findsOneWidget,
    );
  });

  testWidgets('listed but without any time → "No live arrival available", '
      'never "0 min"', (tester) async {
    arrivals.stops = {
      ...fakeStopArrivals(),
      'BSH2': const StopArrivals(
        busStopCode: 'BSH2',
        services: [
          ServiceArrivals(
            serviceNo: 'F20',
            arrivals: [
              BusArrival(
                serviceNo: 'F20',
                busStopCode: 'BSH2',
                estimatedArrival: null,
                source: 'fake',
              ),
            ],
          ),
        ],
      ),
    };
    await pumpApp(tester, app());
    await pick(tester, 'VivoCity', 'VIVOCITY');
    expect(inKey(f20, OptionArrivals.noArrival), findsOneWidget);
    expect(find.textContaining('0 min'), findsNothing);
  });

  testWidgets('provider failure → unavailable + Retry on every option; the '
      'route and MRT stay; Retry recovers', (tester) async {
    arrivals.failure = const NetworkUnavailable();
    await pumpApp(tester, app());
    await pick(tester, 'VivoCity', 'VIVOCITY');

    final message = 'Live arrivals: ${const NetworkUnavailable().message}';
    expect(inKey(f20, message), findsOneWidget);
    expect(inKey(f10, message), findsOneWidget);
    expect(
      inKey('journey-suggested', 'Take Bus F20 toward VivoCity (fake)'),
      findsOneWidget,
    );
    expect(
      inKey('journey-suggested', 'Alight at VIV1 — VivoCity (fake)'),
      findsOneWidget,
    );
    expect(
      inKeyContaining('journey-mrt', 'BISHAN MRT STATION'),
      findsOneWidget,
    );
    expect(find.textContaining('Next buses'), findsNothing);

    arrivals.failure = null;
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key(f20)),
        matching: find.text('Retry'),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(inKey(f20, 'Next buses: Arr · 7 min · 19 min'), findsOneWidget);
    expect(bus.loads, 1, reason: 'Retry does not reload the static route');
  });

  testWidgets('one stop failing does not hide another stop\'s arrivals', (
    tester,
  ) async {
    arrivals.failures['BSH2'] = const BusArrivalUnavailable();
    await pumpApp(tester, app());
    await pick(tester, 'VivoCity', 'VIVOCITY');
    expect(
      inKey(f20, 'Live arrivals: ${const BusArrivalUnavailable().message}'),
      findsOneWidget,
    );
    expect(inKey(f30, 'Next buses: 2 min'), findsOneWidget);
  });

  testWidgets('manual refresh: inside the cache TTL no request is made; '
      'after it, new ETAs appear; the route is not reloaded', (tester) async {
    await pumpApp(tester, app());
    await pick(tester, 'VivoCity', 'VIVOCITY');
    expect(arrivals.totalCalls, 2);

    now = now.add(const Duration(seconds: 5));
    await tester.tap(find.byKey(const Key('arrivals-refresh')));
    await tester.pump();
    await tester.pump();
    expect(arrivals.totalCalls, 2);
    expect(inKey(f20, 'Next buses: Arr · 6 min · 18 min'), findsOneWidget);

    now = now.add(const Duration(minutes: 2));
    arrivals.stops = fakeStopArrivals(from: now);
    await tester.tap(find.byKey(const Key('arrivals-refresh')));
    await tester.pump();
    await tester.pump();
    expect(arrivals.calls, {'BSH2': 2, 'BSH1': 2});
    expect(inKey(f20, 'Next buses: Arr · 7 min · 19 min'), findsOneWidget);
    expect(
      (find.byKey(const Key('arrivals-footer')).evaluate().single.widget
              as Text)
          .data,
      endsWith('checked 12:14 SGT'),
    );
    expect(bus.loads, 1);
  });

  testWidgets('changing the destination while arrivals load: the old '
      'journey\'s answer is never shown on the new one', (tester) async {
    arrivals
      ..hold('BSH2')
      ..hold('BSH1');
    await pumpApp(tester, app());
    await pick(tester, 'VivoCity', 'VIVOCITY');
    expect(inKey(f20, OptionArrivals.checking), findsOneWidget);

    await tester.tap(find.byKey(const Key('change-destination')));
    await tester.pump();
    await pick(tester, 'ION Orchard', 'ION ORCHARD');
    // Bishan → ION Orchard: F30 at BSH1 only.
    expect(find.byKey(const Key(f20)), findsNothing);
    expect(inKey(f30, OptionArrivals.checking), findsOneWidget);

    arrivals.release('BSH2'); // the old journey's stop answers first
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Next buses'), findsNothing);
    expect(inKey(f30, OptionArrivals.checking), findsOneWidget);

    arrivals.release('BSH1');
    await tester.pump();
    await tester.pump();
    expect(inKey(f30, 'Next buses: 2 min'), findsOneWidget);
    expect(find.textContaining(RegExp(r'\bArr\b')), findsNothing);
  });

  testWidgets('a loaded journey\'s arrivals are not shown on the next '
      'journey while its own are loading, even for the same stop', (
    tester,
  ) async {
    await pumpApp(
      tester,
      buildTestApp(
        location: FakeLocationService(
          access: LocationAccess.granted,
          position: bishanGps,
        ),
        environment: FakeEnvironmentRepository(),
        places: FakePlaceSearchRepository(),
        busNetwork: bus,
        mrt: fakeMrtRepository(),
        busArrivals: arrivals,
        busArrivalCacheTtl: Duration.zero, // every check fetches again
        clock: () => now,
      ),
    );
    await pick(tester, 'VivoCity', 'VIVOCITY');
    expect(inKey(f30, 'Next buses: 2 min'), findsOneWidget); // journey A

    arrivals
      ..hold('BSH1')
      ..stops = {
        'BSH1': StopArrivals(
          busStopCode: 'BSH1',
          services: [
            ServiceArrivals(
              serviceNo: 'F30',
              arrivals: [
                fakeArrival('BSH1', 'F30', const Duration(minutes: 9)),
              ],
            ),
          ],
        ),
      };
    await tester.tap(find.byKey(const Key('change-destination')));
    await tester.pump();
    await pick(tester, 'ION Orchard', 'ION ORCHARD'); // journey B: F30 @ BSH1
    expect(inKey(f30, OptionArrivals.checking), findsOneWidget);
    expect(find.text('Next buses: 2 min'), findsNothing);

    arrivals.release('BSH1');
    await tester.pump();
    await tester.pump();
    expect(inKey(f30, 'Next buses: 9 min'), findsOneWidget);
  });

  testWidgets('walk-only and no-direct results request no arrivals', (
    tester,
  ) async {
    await pumpApp(tester, app());
    await pick(tester, 'Bishan MRT', 'BISHAN MRT STATION (NS17)');
    expect(find.byKey(const Key('journey-walk-only')), findsOneWidget);
    expect(find.byKey(const Key('arrivals-refresh')), findsNothing);
    expect(arrivals.totalCalls, 0);
  });
}
