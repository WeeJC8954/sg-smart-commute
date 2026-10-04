// Phase 1 happy-path integration test (guide v2.1 §18, item 1), M1–M4:
// fake GPS inside Singapore → dashboard shows the fake forecast / UV /
// PM2.5 / PSI with scope labels and timestamps → the user searches for and
// selects a destination (fake place search) → a direct-bus suggestion with
// stop, service, stops and estimated walks, plus the MRT alternative (fake
// bus network and MRT asset, integration_test/fakes/fake_bus_network.dart) → live ETAs
// (fake arrivals) → manual refresh updates the ETAs → P2-M1: the optional
// journey map, opened on request, with the journey's markers and the OneMap
// attribution (fake tiles: no live tile is fetched) → P2-M2: the ride line,
// drawn from fake route geometry (no live routes.min.json request) → P2-M3:
// the dashed walking connectors and both MRT suggestion markers; selecting
// another option in the journey card moves the map to it, with no second
// routes.min.json load and no arrival request.
//
// Every provider is a fake and the clock is injected; no live API is called.
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/core/geo/geo.dart';
import 'package:sg_smart_commute/core/location/location_service.dart';
import 'package:sg_smart_commute/features/destination/presentation/destination_card.dart';

import 'fakes/fake_bus_arrival_repository.dart';
import 'fakes/fake_bus_network.dart';
import 'fakes/fake_environment_repository.dart';
import 'fakes/fake_location_service.dart';
import 'fakes/fake_map.dart';
import 'fakes/fake_place_search_repository.dart';
import 'fakes/fake_route_geometry.dart';
import 'fakes/test_app.dart';
import 'support.dart';

void main() {
  initIntegrationTest();

  testWidgets('GPS in Singapore → scoped environmental dashboard → '
      'search and select a destination', (tester) async {
    final env = FakeEnvironmentRepository();
    final places = FakePlaceSearchRepository();
    final arrivals = FakeBusArrivalRepository();
    final tiles = FakeTileProvider();
    final geometry = FakeRouteGeometryRepository();
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
        mapTiles: () => tiles,
        routeGeometry: geometry,
      ),
    );

    await pumpUntilFound(tester, find.text('From: Current location'));

    // Forecast: area scope.
    await pumpUntilFound(tester, inTile('tile-forecast', 'Bishan area'));
    expect(inTile('tile-forecast', 'Partly Cloudy (Day)'), findsOneWidget);
    // UV: national scope.
    expect(inTile('tile-uv', '7'), findsOneWidget);
    expect(inTile('tile-uv', 'High'), findsOneWidget);
    expect(inTile('tile-uv', 'Singapore (national)'), findsOneWidget);

    // PM2.5 and PSI: region scope, separate tiles, separate labels.
    final pm25 = inTile('tile-pm25', '18 µg/m³');
    await tester.ensureVisible(pm25);
    await tester.pump();
    expect(pm25, findsOneWidget);
    expect(inTile('tile-pm25', '1-hr PM2.5'), findsOneWidget); // spec label
    expect(inTile('tile-pm25', 'Normal'), findsOneWidget);
    expect(inTile('tile-pm25', 'Central region'), findsOneWidget);

    final psi = inTile('tile-psi', '54');
    await tester.ensureVisible(psi);
    await tester.pump();
    expect(psi, findsOneWidget);
    expect(inTile('tile-psi', '24-hr PSI'), findsOneWidget); // spec label
    expect(inTile('tile-psi', 'Moderate'), findsOneWidget);
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
    expect(find.text('From: Current location'), findsOneWidget);
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

    // P2-M1: the map is closed until asked for, so no tile was requested.
    expect(find.byKey(const Key('journey-map')), findsNothing);
    expect(tiles.requested, isEmpty);
    await scrollToAndTap(tester, find.byKey(const Key('show-map')));
    await pumpUntilFound(tester, find.byKey(const Key('map-marker-boarding')));
    for (final kind in ['origin', 'alighting', 'destination']) {
      expect(find.byKey(Key('map-marker-$kind')), findsOneWidget);
    }
    // P2-M2: the suggested ride, on the road, from the fake route geometry.
    await pumpUntilFound(tester, find.byKey(const Key('map-ride-line')));
    expect(find.byKey(const Key('map-ride-unavailable')), findsNothing);
    expect(tiles.requested, isNotEmpty);
    final attribution = find.byKey(const Key('basemap-attribution'));
    await tester.ensureVisible(attribution);
    await tester.pump();
    for (final text in ['OneMap', 'Singapore Land Authority']) {
      expect(
        find.descendant(of: attribution, matching: find.text(text)),
        findsOneWidget,
      );
    }

    // P2-M3: straight dashed walking connectors and both MRT suggestions.
    expect(find.byKey(const Key('map-walk-connectors')), findsOneWidget);
    expect(find.byKey(const Key('map-marker-mrtNearOrigin')), findsOneWidget);
    expect(
      find.byKey(const Key('map-marker-mrtNearDestination')),
      findsOneWidget,
    );
    // Selecting F10 in the journey card moves the map to it: no second
    // routes.min.json load and no arrival request.
    final callsBefore = arrivals.totalCalls;
    await scrollToAndTap(tester, find.byKey(const Key('select-option-F10')));
    await pumpUntilFound(tester, find.byKey(const Key('selected-option-F10')));
    await tester.pump();
    final boarding = tester
        .widget<MarkerLayer>(find.byType(MarkerLayer))
        .markers
        .firstWhere((m) => m.key == const Key('map-marker-boarding'))
        .point;
    final bsh1 = fakeBusNetwork().stops['BSH1']!.position;
    expect(boarding.latitude, bsh1.latitude);
    expect(boarding.longitude, bsh1.longitude);
    expect(find.byKey(const Key('map-ride-line')), findsOneWidget);
    expect(geometry.loads, 1);
    expect(arrivals.totalCalls, callsBefore);
  });
}
