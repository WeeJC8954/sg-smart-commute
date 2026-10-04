// Phase 1 fallback/error-path integration test (guide v2.1 §18, item 2),
// M1–M4: permission denied (or a fix outside Singapore, or a timeout) → the
// manual origin prompt appears → the user searches for and selects an origin
// → searches for and selects a destination → "No direct bus found" plus the
// MRT alternative (fake bus network and MRT asset) → P2-M3: the map, opened
// on request, marks the two ends and both MRT suggestions, with no bus stops,
// walking connectors, legend or route-geometry request, and is hidden again →
// a provider fails (24-hr
// PSI throws NetworkUnavailable) → a clear error with Retry and no
// fabricated value → Retry with the recovered fake succeeds → the user
// changes the origin to one with a direct bus → the bus-arrival provider
// fails (NetworkUnavailable): the route stays visible, arrivals show as
// unavailable with Retry, and no ETA is fabricated → Retry with the
// recovered fake shows the ETA.
//
// Every provider is a fake; no live API is called. The 10 s timeout is injected (short), so the test never
// waits 10 s in real time.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/core/errors/app_failure.dart';
import 'package:sg_smart_commute/core/geo/geo.dart';
import 'package:sg_smart_commute/core/location/location_service.dart';
import 'package:sg_smart_commute/features/destination/presentation/destination_card.dart';
import 'package:sg_smart_commute/features/origin/presentation/origin_card.dart';

import 'fakes/fake_bus_arrival_repository.dart';
import 'fakes/fake_environment_repository.dart';
import 'fakes/fake_location_service.dart';
import 'fakes/fake_route_geometry.dart';
import 'fakes/test_app.dart';
import 'support.dart';

void main() {
  initIntegrationTest();

  testWidgets('permission denied → search origin → search destination → '
      'provider failure → Retry recovers', (tester) async {
    final location = FakeLocationService(access: LocationAccess.denied);
    final env = FakeEnvironmentRepository()
      ..failPsi = const NetworkUnavailable();
    final arrivals = FakeBusArrivalRepository()
      ..failure = const NetworkUnavailable();
    final geometry = FakeRouteGeometryRepository();
    await tester.pumpWidget(
      buildTestApp(
        location: location,
        environment: env,
        busArrivals: arrivals,
        routeGeometry: geometry,
      ),
    );

    // Manual prompt immediately; no position was ever requested.
    await pumpUntilFound(tester, find.text(OriginCard.fallbackPrompt));
    expect(location.positionRequests, 0);

    await searchAndPick(
      tester,
      field: const Key('manual-origin-field'),
      query: 'Tampines Hub',
      result: 'OUR TAMPINES HUB',
    );
    await pumpUntilFound(tester, find.text('From: OUR TAMPINES HUB'));

    // M2: destination search after the manual origin.
    await pumpUntilFound(tester, find.text(DestinationCard.prompt));
    await searchAndPick(
      tester,
      field: const Key('destination-field'),
      query: '238801',
      result: 'ION ORCHARD',
    );
    await pumpUntilFound(tester, find.text('To: ION ORCHARD'));
    expect(find.text('From: OUR TAMPINES HUB'), findsOneWidget);

    // M3: no single fake service connects Tampines Hub and ION Orchard.
    await pumpUntilFound(tester, find.byKey(const Key('journey-no-direct')));
    expect(find.text('No direct bus found'), findsOneWidget);
    expect(find.textContaining('Take Bus'), findsNothing);
    final mrt = find.byKey(const Key('journey-mrt'));
    await tester.ensureVisible(mrt);
    await tester.pump();
    expect(
      find.descendant(
        of: mrt,
        matching: find.textContaining('Nearest MRT: TAMPINES MRT STATION'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: mrt,
        matching: find.textContaining(
          'Near your destination: ORCHARD MRT STATION',
        ),
      ),
      findsOneWidget,
    );

    // P2-M3: the map marks the two ends and both MRT suggestions only. No
    // bus, so no stops, connectors, legend or routes.min.json request.
    await scrollToAndTap(tester, find.byKey(const Key('show-map')));
    await pumpUntilFound(
      tester,
      find.byKey(const Key('map-marker-mrtNearOrigin')),
    );
    for (final kind in ['origin', 'destination', 'mrtNearDestination']) {
      expect(find.byKey(Key('map-marker-$kind')), findsOneWidget, reason: kind);
    }
    for (final key in [
      'map-marker-boarding',
      'map-walk-connectors',
      'map-legend',
      'map-ride-line',
    ]) {
      expect(find.byKey(Key(key)), findsNothing, reason: key);
    }
    expect(geometry.loads, 0);
    await scrollToAndTap(tester, find.byKey(const Key('hide-map')));
    await tester.pump();

    await pumpUntilFound(tester, inTile('tile-forecast', 'Tampines area'));

    // PSI failed: clear message + Retry, and no PSI value is shown.
    final error = inTile('tile-psi', const NetworkUnavailable().message);
    await tester.ensureVisible(error);
    await tester.pump();
    expect(error, findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('tile-psi')),
        matching: find.textContaining('24-hr PSI '),
      ),
      findsNothing,
    );
    // The other region tile is unaffected.
    expect(inTile('tile-pm25', '13 µg/m³'), findsOneWidget);
    expect(inTile('tile-pm25', 'Normal'), findsOneWidget);

    // Recover and retry.
    env.failPsi = null;
    await scrollToAndTap(
      tester,
      find.descendant(
        of: find.byKey(const Key('tile-psi')),
        matching: find.text('Retry'),
      ),
    );
    await pumpUntilFound(tester, inTile('tile-psi', '61'));
    expect(inTile('tile-psi', 'East region'), findsOneWidget);
    expect(env.calls['psi'], 2);

    // M4: no bus option was shown yet, so no arrivals were requested.
    expect(arrivals.totalCalls, 0);

    // A new origin with a direct bus: Bishan → ION Orchard, F30 from BSH1.
    await scrollToTop(tester);
    await scrollToAndTap(tester, find.byKey(const Key('change-origin')));
    await searchAndPick(
      tester,
      field: const Key('manual-origin-field'),
      query: 'Bishan MRT',
      result: 'BISHAN MRT STATION (NS17)',
    );
    final suggested = find.byKey(const Key('journey-suggested'));
    await pumpUntilFound(tester, suggested);

    // Arrivals fail: the route stays, arrivals are unavailable with Retry.
    final f30 = find.byKey(const Key('arrivals-BSH1-F30'));
    final unavailable = find.descendant(
      of: f30,
      matching: find.text(
        'Live arrivals: ${const NetworkUnavailable().message}',
      ),
    );
    await pumpUntilFound(tester, unavailable);
    await tester.ensureVisible(suggested);
    await tester.pump();
    expect(
      find.descendant(
        of: suggested,
        matching: find.text('Take Bus F30 toward VivoCity (fake)'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: suggested,
        matching: find.text('Alight at ION1 — Orchard Stn (fake)'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Next buses'), findsNothing);

    // The provider recovers; Retry shows the ETA.
    arrivals.failure = null;
    await scrollToAndTap(
      tester,
      find.descendant(of: f30, matching: find.text('Retry')),
    );
    await pumpUntilFound(
      tester,
      find.descendant(of: f30, matching: find.text('Next buses: 2 min')),
    );
    expect(arrivals.calls['BSH1'], 2);
  });

  testWidgets('fix outside Singapore → manual origin', (tester) async {
    await tester.pumpWidget(
      buildTestApp(
        location: FakeLocationService(
          access: LocationAccess.granted,
          position: const LatLng(37.4220, -122.0841), // emulator default
        ),
        environment: FakeEnvironmentRepository(),
      ),
    );
    await pumpUntilFound(tester, find.text(OriginCard.fallbackPrompt));
    expect(
      find.text('Your reported location is outside Singapore.'),
      findsOneWidget,
    );
  });

  testWidgets('no fix before the (injected) timeout → manual origin, '
      'and the late fix does not overwrite the manual choice', (tester) async {
    final location = FakeLocationService(access: LocationAccess.granted);
    await tester.pumpWidget(
      buildTestApp(
        location: location,
        environment: FakeEnvironmentRepository(),
        locationTimeout: const Duration(milliseconds: 200),
      ),
    );
    await pumpUntilFound(tester, find.text(OriginCard.fallbackPrompt));
    expect(find.text('Finding your location took too long.'), findsOneWidget);

    await searchAndPick(
      tester,
      field: const Key('manual-origin-field'),
      query: 'ION Orchard',
      result: 'ION ORCHARD',
    );
    location.fix(const LatLng(1.3508, 103.8485)); // late, valid
    await pumpUntilFound(tester, find.byKey(const Key('use-current-location')));
    expect(find.text('From: ION ORCHARD'), findsOneWidget);
  });
}
