// Phase 1 happy-path integration test (guide v2.1 §18, item 1), M1–M4:
// fake GPS inside Singapore → dashboard shows the fake forecast / UV /
// PM2.5 / PSI with scope labels and timestamps → the user searches for and
// selects a destination (fake place search) → a direct-bus suggestion with
// stop, service, stops and estimated walks, plus the MRT alternative (fake
// bus network and MRT asset, test/fakes/fake_bus_network.dart) → live ETAs
// (fake arrivals) → manual refresh updates the ETAs.
//
// Every provider is a fake and the clock is injected; no live API is called.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sg_smart_commute/core/geo/geo.dart';
import 'package:sg_smart_commute/core/location/location_service.dart';
import 'package:sg_smart_commute/features/destination/presentation/destination_card.dart';

import '../test/fakes/fake_bus_arrival_repository.dart';
import '../test/fakes/fake_environment_repository.dart';
import '../test/fakes/fake_location_service.dart';
import '../test/fakes/fake_place_search_repository.dart';
import '../test/fakes/test_app.dart';
import 'support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('GPS in Singapore → scoped environmental dashboard → '
      'search and select a destination', (tester) async {
    final env = FakeEnvironmentRepository();
    final places = FakePlaceSearchRepository();
    final arrivals = FakeBusArrivalRepository();
    var now = fakeNow;
    await tester.pumpWidget(
      buildTestApp(
        location: FakeLocationService(
          access: LocationAccess.granted,
          position: const LatLng(1.3508, 103.8485), // Bishan
        ),
        environment: env,
        places: places,
        busArrivals: arrivals,
        clock: () => now,
      ),
    );

    await pumpUntilFound(
      tester,
      find.text('From: Current location (from GPS)'),
    );

    // Forecast: area scope.
    await pumpUntilFound(tester, inTile('tile-forecast', 'Bishan area'));
    expect(inTile('tile-forecast', 'Partly Cloudy (Day)'), findsOneWidget);
    // UV: national scope.
    expect(inTile('tile-uv', 'UV 7 (High)'), findsOneWidget);
    expect(inTile('tile-uv', 'Singapore (national)'), findsOneWidget);

    // PM2.5 and PSI: region scope, separate tiles, separate labels.
    final pm25 = inTile('tile-pm25', '1-hr PM2.5 18 µg/m³ (Normal)');
    await tester.ensureVisible(pm25);
    await tester.pump();
    expect(pm25, findsOneWidget);
    expect(inTile('tile-pm25', 'Central region'), findsOneWidget);

    final psi = inTile('tile-psi', '24-hr PSI 54 (Moderate)');
    await tester.ensureVisible(psi);
    await tester.pump();
    expect(psi, findsOneWidget);
    expect(inTile('tile-psi', 'Central region'), findsOneWidget);
    expect(inTile('tile-psi', 'As of 12:00 SGT · 12 min ago'), findsOneWidget);

    // One fetch per dataset at launch.
    expect(env.calls, {'forecast': 1, 'uv': 1, 'pm25': 1, 'psi': 1});
    expect(find.byKey(const Key('manual-origin-field')), findsNothing);

    // M2: destination search (same component as the manual origin).
    await scrollToTop(tester);
    await pumpUntilFound(tester, find.text(DestinationCard.prompt));
    await searchAndPick(
      tester,
      field: const Key('destination-field'),
      query: 'VivoCity',
      result: 'VIVOCITY',
    );
    await pumpUntilFound(tester, find.text('To: VIVOCITY'));
    // Choosing a destination does not change the GPS origin.
    expect(find.text('From: Current location (from GPS)'), findsOneWidget);
    expect(places.queries, ['vivocity']);

    // M3: direct-bus recommendation (fake network) and MRT alternative.
    await pumpUntilFound(tester, find.byKey(const Key('journey-suggested')));
    final suggested = find.byKey(const Key('journey-suggested'));
    await tester.ensureVisible(suggested);
    await tester.pump();
    expect(
      find.descendant(
        of: suggested,
        matching: find.text('Take Bus F20 toward VivoCity (fake)'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: suggested,
        matching: find.textContaining('to Bus Stop BSH2 — Opp Bishan Stn'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: suggested, matching: find.text('2 stops')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('journey-alternative-1')), findsOneWidget);

    // M4: live ETAs for the displayed option's boarding stop and service.
    final eta = find.byKey(const Key('arrivals-BSH2-F20'));
    await pumpUntilFound(
      tester,
      find.descendant(
        of: eta,
        matching: find.text('Next buses: Arr · 7 min · 19 min'),
      ),
    );
    expect(arrivals.calls, {'BSH2': 1, 'BSH1': 1});

    // Manual refresh, after the cache TTL: new ETAs, the route is unchanged.
    now = now.add(const Duration(minutes: 2));
    arrivals.stops = fakeStopArrivals(
      from: now.add(const Duration(minutes: 3)),
    );
    await scrollToAndTap(tester, find.byKey(const Key('arrivals-refresh')));
    await pumpUntilFound(
      tester,
      find.descendant(
        of: eta,
        matching: find.text('Next buses: 3 min · 10 min · 22 min'),
      ),
    );
    expect(arrivals.calls, {'BSH2': 2, 'BSH1': 2});
    expect(
      find.descendant(
        of: suggested,
        matching: find.text('Take Bus F20 toward VivoCity (fake)'),
      ),
      findsOneWidget,
    );
    final mrt = find.byKey(const Key('journey-mrt'));
    await tester.ensureVisible(mrt);
    await tester.pump();
    expect(
      find.descendant(
        of: mrt,
        matching: find.textContaining('Nearest MRT: BISHAN MRT STATION'),
      ),
      findsOneWidget,
    );
  });
}
