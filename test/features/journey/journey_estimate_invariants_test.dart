// E2 invariants (plan §8 T3): the estimate is display-only. It never changes
// the planner's order or scores, never requests arrivals, route geometry or
// bus data beyond what the journey already did, and lives only in the
// journey domain and card. Each guard is proven by a deliberate mutation
// (plan §9).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/core/geo/geo.dart';
import 'package:sg_smart_commute/core/location/location_service.dart';
import 'package:sg_smart_commute/features/journey/domain/bus_network.dart';
import 'package:sg_smart_commute/features/journey/domain/direct_bus_planner.dart';
import 'package:sg_smart_commute/features/journey/domain/journey_estimate.dart';

import '../../../integration_test/fakes/fake_bus_arrival_repository.dart';
import '../../../integration_test/fakes/fake_bus_network.dart';
import '../../../integration_test/fakes/fake_environment_repository.dart';
import '../../../integration_test/fakes/fake_location_service.dart';
import '../../../integration_test/fakes/fake_place_search_repository.dart';
import '../../../integration_test/fakes/fake_route_geometry.dart';
import '../../../integration_test/fakes/test_app.dart';

const bishan = LatLng(1.3508, 103.8485);
const destinationField = Key('destination-field');

BusStop stop(String code, double lat, double lng) => BusStop(
  code: code,
  position: LatLng(lat, lng),
  name: code,
  road: 'Test Rd',
);

BusService svc(String number, List<List<String>> directions) =>
    BusService(number: number, name: 'Test $number', directions: directions);

/// X: two stops, far out and back (long). Y: four stops, straight (short).
/// The planner's score prefers X (fewer stops); E2's estimate would prefer Y.
final rankingStops = [
  stop('O', 1.300, 103.800),
  stop('FAR', 1.400, 103.900),
  stop('Y1', 1.3045, 103.800),
  stop('Y2', 1.3090, 103.800),
  stop('Y3', 1.3135, 103.800),
  stop('D', 1.318, 103.800),
];
final rankingNetwork = BusNetwork(
  stops: {for (final s in rankingStops) s.code: s},
  services: {
    for (final s in [
      svc('X', [
        ['O', 'FAR', 'D'],
      ]),
      svc('Y', [
        ['O', 'Y1', 'Y2', 'Y3', 'D'],
      ]),
    ])
      s.number: s,
  },
);

Finder inKey(Key key, Finder f) =>
    find.descendant(of: find.byKey(key), matching: f);

Key tripKey(String board, String service) =>
    Key('trip-estimate-$board-$service');

Future<void> searchAndPick(
  WidgetTester tester,
  String query,
  String result,
) async {
  await tester.enterText(find.byKey(destinationField), query);
  await tester.pump(pastSearchDebounce);
  await tester.pump();
  await tester.tap(find.text(result));
  await tester.pump();
  await tester.pump();
}

Future<void> tapVisible(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await tester.pump();
  await tester.pump();
}

/// Lines of [path] that import something.
List<String> importsOf(String path) => [
  for (final line in File(path).readAsLinesSync())
    if (line.trimLeft().startsWith('import ')) line.trim(),
];

void main() {
  group('the planner ranking is unchanged (T3.1)', () {
    test('order and scores follow the stop-count score, not the estimate', () {
      final plan = planDirectBus(
        rankingNetwork,
        rankingStops.first.position,
        rankingStops.last.position,
      );
      expect(plan, isA<DirectBusOptions>());
      final options = (plan as DirectBusOptions).options;
      expect([for (final o in options) o.service.number], ['X', 'Y']);
      // walk 0 + walk 0 + 1.5 × stops, exactly.
      expect([for (final o in options) o.score], [3.0, 6.0]);
      final x = estimateDirectJourney(options[0], rankingNetwork)!;
      final y = estimateDirectJourney(options[1], rankingNetwork)!;
      // The estimate would put Y first: it is not in the ranking.
      expect(x.partsMinutes, greaterThan(y.partsMinutes));
    });

    testWidgets('Suggested stays the planner\'s first option', (tester) async {
      final places = FakePlaceSearchRepository()
        ..results['ranking end'] = [
          fakePlace('RANKING END', lat: 1.318, lng: 103.800),
        ];
      tester.view.physicalSize = const Size(1080, 5000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        buildTestApp(
          location: FakeLocationService(
            access: LocationAccess.granted,
            position: const LatLng(1.300, 103.800),
          ),
          environment: FakeEnvironmentRepository(),
          places: places,
          busNetwork: FakeBusNetworkRepository(network: rankingNetwork),
          mrt: fakeMrtRepository(),
          busArrivals: FakeBusArrivalRepository(),
        ),
      );
      await tester.pump();
      await searchAndPick(tester, 'Ranking End', 'RANKING END');
      expect(
        inKey(
          const Key('journey-suggested'),
          find.textContaining('Take Bus X toward'),
        ),
        findsOneWidget,
      );
      expect(
        inKey(
          const Key('journey-alternative-1'),
          find.textContaining('Take Bus Y toward'),
        ),
        findsOneWidget,
      );
      // Both still show their own estimate.
      expect(find.byKey(tripKey('O', 'X')), findsOneWidget);
      expect(find.byKey(tripKey('O', 'Y')), findsOneWidget);
    });
  });

  group('no new request (T3.2–T3.4, T3.6)', () {
    late FakeBusNetworkRepository bus;
    late FakeBusArrivalRepository arrivals;
    late FakeRouteGeometryRepository geometry;

    setUp(() {
      bus = FakeBusNetworkRepository();
      arrivals = FakeBusArrivalRepository();
      geometry = FakeRouteGeometryRepository();
    });

    Future<void> toVivoCity(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 5000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        buildTestApp(
          location: FakeLocationService(
            access: LocationAccess.granted,
            position: bishan,
          ),
          environment: FakeEnvironmentRepository(),
          places: FakePlaceSearchRepository(),
          busNetwork: bus,
          mrt: fakeMrtRepository(),
          busArrivals: arrivals,
          routeGeometry: geometry,
        ),
      );
      await tester.pump();
      await searchAndPick(tester, 'VivoCity', 'VIVOCITY');
      await tester.pump();
      expect(find.byKey(tripKey('BSH2', 'F20')), findsOneWidget);
    }

    testWidgets('arrivals: one request per boarding stop, and Refresh '
        'changes no estimate', (tester) async {
      await toVivoCity(tester);
      expect(arrivals.calls, {'BSH2': 1, 'BSH1': 1});
      final trips = [
        for (final k in [tripKey('BSH2', 'F20'), tripKey('BSH1', 'F10')])
          tester.widget<Text>(inKey(k, find.byType(Text))).data,
      ];
      await tapVisible(tester, find.text('Refresh arrivals'));
      expect(arrivals.calls, {'BSH2': 1, 'BSH1': 1}); // inside the cache TTL
      expect([
        for (final k in [tripKey('BSH2', 'F20'), tripKey('BSH1', 'F10')])
          tester.widget<Text>(inKey(k, find.byType(Text))).data,
      ], trips);
    });

    testWidgets('no route geometry while the map is closed; one load when '
        'it opens, as before E2', (tester) async {
      await toVivoCity(tester);
      expect(geometry.loads, 0);
      await tapVisible(tester, find.byKey(const Key('show-map')));
      expect(geometry.loads, 1);
    });

    testWidgets('bus data loads once across a new destination', (tester) async {
      await toVivoCity(tester);
      expect(bus.loads, 1);
      await tapVisible(tester, find.byKey(const Key('change-destination')));
      await searchAndPick(tester, 'ION Orchard', 'ION ORCHARD');
      expect(find.byKey(tripKey('BSH1', 'F30')), findsOneWidget);
      expect(bus.loads, 1);
      expect(geometry.loads, 0);
    });

    testWidgets('selecting an option keeps every estimate and loads nothing', (
      tester,
    ) async {
      await toVivoCity(tester);
      await tapVisible(tester, find.byKey(const Key('select-option-F10')));
      expect(find.byKey(const Key('selected-option-F10')), findsOneWidget);
      for (final k in [
        tripKey('BSH2', 'F20'),
        tripKey('BSH1', 'F10'),
        tripKey('BSH1', 'F30'),
      ]) {
        expect(find.byKey(k), findsOneWidget);
      }
      expect(bus.loads, 1);
      expect(geometry.loads, 0);
    });
  });

  group('the estimate lives only in the journey domain and card (T3.5)', () {
    const estimator = 'lib/features/journey/domain/journey_estimate.dart';

    test('the estimator imports only config, geo and journey domain', () {
      expect(importsOf(estimator), [
        "import '../../../core/config/app_config.dart';",
        "import '../../../core/geo/geo.dart';",
        "import 'bus_network.dart';",
        "import 'direct_bus_planner.dart';",
      ]);
    });

    test('only the journey card uses it', () {
      final users = [
        for (final f in Directory('lib').listSync(recursive: true))
          if (f is File &&
              f.path.endsWith('.dart') &&
              importsOf(f.path).any((i) => i.contains('journey_estimate.dart')))
            f.path.replaceAll(r'\', '/'),
      ];
      expect(users, ['lib/features/journey/presentation/journey_card.dart']);
    });

    test('the journey feature never imports the map feature', () {
      final offenders = [
        for (final f in Directory(
          'lib/features/journey',
        ).listSync(recursive: true))
          if (f is File && f.path.endsWith('.dart'))
            for (final i in importsOf(f.path))
              if (i.contains('/map/')) '${f.path}: $i',
      ];
      expect(offenders, isEmpty);
    });
  });
}
