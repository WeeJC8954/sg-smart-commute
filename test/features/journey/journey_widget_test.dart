// Milestone 3 widget tests: the journey result (guide v2.1 §5.6, §9, §18).
// Location, environment, place search, bus data and the MRT asset are fakes
// (test/fakes/). No arrival times are shown anywhere in M3.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/core/errors/app_failure.dart';
import 'package:sg_smart_commute/core/geo/geo.dart';
import 'package:sg_smart_commute/core/location/location_service.dart';
import 'package:sg_smart_commute/features/journey/domain/walking.dart';
import 'package:sg_smart_commute/features/journey/presentation/journey_card.dart';
import 'package:sg_smart_commute/features/places/domain/place.dart';

import '../../fakes/fake_bus_network.dart';
import '../../fakes/fake_environment_repository.dart';
import '../../fakes/fake_location_service.dart';
import '../../fakes/fake_place_search_repository.dart';
import '../../fakes/test_app.dart';

const bishan = LatLng(1.3508, 103.8485);
const originField = Key('manual-origin-field');
const destinationField = Key('destination-field');

Future<void> pumpApp(WidgetTester tester, Widget app) async {
  tester.view.physicalSize = const Size(1080, 5000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
  await tester.pump();
}

Future<void> searchAndPick(
  WidgetTester tester,
  Key field,
  String query,
  String result,
) async {
  await tester.enterText(find.byKey(field), query);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
  await tester.tap(find.text(result));
  await tester.pump();
  await tester.pump();
}

Finder inCard(String text) => find.descendant(
  of: find.byKey(const Key('journey-card')),
  matching: find.text(text),
);

Finder inKey(String key, String text) =>
    find.descendant(of: find.byKey(Key(key)), matching: find.text(text));

String walk(LatLng a, LatLng b) => WalkEstimate.between(a, b).label;

void main() {
  late FakeBusNetworkRepository bus;
  late FakePlaceSearchRepository places;
  final stops = fakeBusNetwork().stops;

  setUp(() {
    bus = FakeBusNetworkRepository();
    places = FakePlaceSearchRepository();
  });

  Widget gpsApp({FakeBusNetworkRepository? network, bool mrtFails = false}) =>
      buildTestApp(
        location: FakeLocationService(
          access: LocationAccess.granted,
          position: bishan,
        ),
        environment: FakeEnvironmentRepository(),
        places: places,
        busNetwork: network ?? bus,
        mrt: fakeMrtRepository(fail: mrtFails),
      );

  Widget deniedApp() => buildTestApp(
    location: FakeLocationService(access: LocationAccess.denied),
    environment: FakeEnvironmentRepository(),
    places: places,
    busNetwork: bus,
    mrt: fakeMrtRepository(),
  );

  testWidgets('no journey card, and no bus data load, until both ends exist', (
    tester,
  ) async {
    await pumpApp(tester, gpsApp());
    expect(find.byKey(const Key('journey-card')), findsNothing);
    expect(bus.loads, 0);
  });

  testWidgets('loading → Suggested direct bus with alternatives', (
    tester,
  ) async {
    bus.hold();
    await pumpApp(tester, gpsApp());
    await searchAndPick(tester, destinationField, 'VivoCity', 'VIVOCITY');
    expect(inCard('Finding a direct bus…'), findsOneWidget);
    expect(bus.loads, 1);

    bus.release();
    await tester.pump();
    await tester.pump();

    // Suggested: F20 from BSH2 (score 6); then F10 and F30 (6.5, tie → number).
    final s = 'journey-suggested';
    expect(inKey(s, 'Suggested'), findsOneWidget);
    expect(
      inKey(
        s,
        '${walk(bishan, stops['BSH2']!.position)} to Bus Stop BSH2 — '
        'Opp Bishan Stn (fake)',
      ),
      findsOneWidget,
    );
    expect(inKey(s, 'Take Bus F20 toward VivoCity (fake)'), findsOneWidget);
    expect(inKey(s, '2 stops'), findsOneWidget);
    expect(inKey(s, 'Alight at VIV1 — VivoCity (fake)'), findsOneWidget);
    expect(
      inKey(
        s,
        '${walk(stops['VIV1']!.position, vivoCity.position)} to destination',
      ),
      findsOneWidget,
    );

    expect(inCard('Alternatives'), findsOneWidget);
    expect(
      inKey(
        'journey-alternative-1',
        'Take Bus F10 toward Opp Bishan Stn (fake)',
      ),
      findsNothing, // direction 0 of F10 ends at VIV1
    );
    expect(
      inKey('journey-alternative-1', 'Take Bus F10 toward VivoCity (fake)'),
      findsOneWidget,
    );
    expect(
      inKey('journey-alternative-2', 'Take Bus F30 toward VivoCity (fake)'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('journey-alternative-3')), findsNothing);

    // Estimates are labelled as estimates; no arrival time is invented.
    expect(find.textContaining('min walk (est.)'), findsWidgets);
    expect(inCard(JourneyCard.noArrivals), findsOneWidget);
    expect(inCard(JourneyCard.estimateNote), findsOneWidget);
    expect(find.textContaining(RegExp(r'\b(Arr|arriving)\b')), findsNothing);
  });

  testWidgets(
    'MRT alternative: nearest station at each end, by name and walk',
    (tester) async {
      await pumpApp(tester, gpsApp());
      await searchAndPick(tester, destinationField, 'VivoCity', 'VIVOCITY');
      expect(
        inKey(
          'journey-mrt',
          'Nearest MRT: BISHAN MRT STATION — '
              '${walk(bishan, const LatLng(1.3510, 103.8483))}',
        ),
        findsOneWidget,
      );
      expect(
        inKey(
          'journey-mrt',
          'Near your destination: HARBOURFRONT MRT STATION — '
              '${walk(vivoCity.position, const LatLng(1.2653, 103.8220))}',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('changing the destination recalculates the recommendation', (
    tester,
  ) async {
    await pumpApp(tester, gpsApp());
    await searchAndPick(tester, destinationField, 'VivoCity', 'VIVOCITY');
    expect(
      inKey('journey-suggested', 'Take Bus F20 toward VivoCity (fake)'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('change-destination')));
    await tester.pump();
    await searchAndPick(tester, destinationField, 'ION Orchard', 'ION ORCHARD');
    expect(
      inKey('journey-suggested', 'Take Bus F30 toward VivoCity (fake)'),
      findsOneWidget,
    );
    expect(inKey('journey-suggested', '1 stop'), findsOneWidget);
    expect(
      inKey('journey-suggested', 'Alight at ION1 — Orchard Stn (fake)'),
      findsOneWidget,
    );
    expect(bus.loads, 1, reason: 'static data stays cached for the session');
  });

  testWidgets('changing the origin recalculates the recommendation', (
    tester,
  ) async {
    await pumpApp(tester, gpsApp());
    await searchAndPick(tester, destinationField, 'ION Orchard', 'ION ORCHARD');
    expect(
      inKey('journey-suggested', 'Take Bus F30 toward VivoCity (fake)'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('change-origin')));
    await tester.pump();
    await searchAndPick(
      tester,
      originField,
      'Tampines Hub',
      'OUR TAMPINES HUB',
    );
    expect(find.byKey(const Key('journey-no-direct')), findsOneWidget);
    expect(inCard('No direct bus found'), findsOneWidget);
    expect(find.byKey(const Key('journey-suggested')), findsNothing);
  });

  testWidgets('no direct bus → clear state plus the MRT alternative', (
    tester,
  ) async {
    await pumpApp(tester, deniedApp());
    await searchAndPick(
      tester,
      originField,
      'Tampines Hub',
      'OUR TAMPINES HUB',
    );
    await searchAndPick(tester, destinationField, '238801', 'ION ORCHARD');
    expect(inCard('No direct bus found'), findsOneWidget);
    expect(inCard(JourneyCard.noArrivals), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('journey-mrt')),
        matching: find.textContaining('TAMPINES MRT STATION'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('journey-mrt')),
        matching: find.textContaining('ORCHARD MRT STATION'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('static data unavailable → clear error, Retry, MRT still shown; '
      'nothing fabricated', (tester) async {
    bus.failure = const StaticDataUnavailable('busrouter');
    await pumpApp(tester, gpsApp());
    await searchAndPick(tester, destinationField, 'VivoCity', 'VIVOCITY');
    expect(inCard('Bus data is unavailable right now.'), findsOneWidget);
    expect(find.byKey(const Key('journey-suggested')), findsNothing);
    expect(find.textContaining('Take Bus'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('journey-mrt')),
        matching: find.textContaining('BISHAN MRT STATION'),
      ),
      findsOneWidget,
    );

    bus.failure = null;
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('journey-card')),
        matching: find.text('Retry'),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(
      inKey('journey-suggested', 'Take Bus F20 toward VivoCity (fake)'),
      findsOneWidget,
    );
    expect(bus.loads, 2);
  });

  testWidgets('MRT asset unavailable → its own message; the bus plan is kept', (
    tester,
  ) async {
    await pumpApp(tester, gpsApp(mrtFails: true));
    await searchAndPick(tester, destinationField, 'VivoCity', 'VIVOCITY');
    expect(
      inKey('journey-mrt', 'MRT station data is unavailable.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('journey-suggested')), findsOneWidget);
  });

  testWidgets(
    'walk-only: a destination within 300 m, without loading bus data',
    (tester) async {
      places.results['bishan park'] = [
        fakePlace('BISHAN PARK EDGE', lat: 1.3520, lng: 103.8500),
      ];
      await pumpApp(tester, gpsApp());
      await searchAndPick(
        tester,
        destinationField,
        'Bishan Park',
        'BISHAN PARK EDGE',
      );
      expect(find.byKey(const Key('journey-walk-only')), findsOneWidget);
      expect(
        find.textContaining(
          'Your destination is close: '
          '${walk(bishan, const LatLng(1.3520, 103.8500))}',
        ),
        findsOneWidget,
      );
      expect(bus.loads, 0);
    },
  );

  testWidgets('no bus stop nearby → says so for the right end', (tester) async {
    places.results['pulau ubin'] = [
      fakePlace(
        'PULAU UBIN JETTY',
        lat: 1.4040,
        lng: 103.9600,
        type: PlaceType.poi,
      ),
    ];
    await pumpApp(tester, gpsApp());
    await searchAndPick(
      tester,
      destinationField,
      'Pulau Ubin',
      'PULAU UBIN JETTY',
    );
    expect(
      inCard('No bus stop within 800 m of your destination.'),
      findsOneWidget,
    );
  });
}
