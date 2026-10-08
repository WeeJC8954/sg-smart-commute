// Milestone 3 widget tests: the journey result (guide v2.1 §5.6, §9, §18).
// Location, environment, place search, bus data and the MRT asset are fakes
// (integration_test/fakes/). No arrival times are shown anywhere in M3.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/core/config/app_config.dart';
import 'package:sg_smart_commute/core/errors/app_failure.dart';
import 'package:sg_smart_commute/core/geo/geo.dart';
import 'package:sg_smart_commute/core/location/location_service.dart';
import 'package:sg_smart_commute/core/ui/motion.dart';
import 'package:sg_smart_commute/features/bus_arrival/bus_arrival_providers.dart';
import 'package:sg_smart_commute/features/journey/domain/walking.dart';
import 'package:sg_smart_commute/features/journey/journey_providers.dart';
import 'package:sg_smart_commute/features/journey/presentation/journey_card.dart';
import 'package:sg_smart_commute/features/places/domain/place.dart';

import '../../../integration_test/fakes/fake_bus_arrival_repository.dart';
import '../../../integration_test/fakes/fake_bus_network.dart';
import '../../../integration_test/fakes/fake_environment_repository.dart';
import '../../../integration_test/fakes/fake_location_service.dart';
import '../../../integration_test/fakes/fake_place_search_repository.dart';
import '../../../integration_test/fakes/test_app.dart';

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
  await tester.pump(pastSearchDebounce);
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

/// The text of a keyed [Text] (the key sits on the Text itself).
String textOf(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

String walk(LatLng a, LatLng b) => WalkEstimate.between(a, b).label;

/// Taps the "Select" control of [service]'s option (P2-M3).
Future<void> select(WidgetTester tester, String service) async {
  final button = find.byKey(Key('select-option-$service'));
  await tester.ensureVisible(button);
  await tester.pump();
  await tester.tap(button);
  await tester.pump();
  await tester.pump();
}

void main() {
  late FakeBusNetworkRepository bus;
  late FakePlaceSearchRepository places;
  late FakeBusArrivalRepository arrivals;
  final stops = fakeBusNetwork().stops;

  setUp(() {
    bus = FakeBusNetworkRepository();
    places = FakePlaceSearchRepository();
    arrivals = FakeBusArrivalRepository();
  });

  Widget gpsApp({
    FakeBusNetworkRepository? network,
    bool mrtFails = false,
    double? mrtMaxDistanceMeters,
  }) => buildTestApp(
    location: FakeLocationService(
      access: LocationAccess.granted,
      position: bishan,
    ),
    environment: FakeEnvironmentRepository(),
    places: places,
    busNetwork: network ?? bus,
    mrt: fakeMrtRepository(fail: mrtFails),
    mrtMaxDistanceMeters: mrtMaxDistanceMeters,
    busArrivals: arrivals,
  );

  Widget deniedApp() => buildTestApp(
    location: FakeLocationService(access: LocationAccess.denied),
    environment: FakeEnvironmentRepository(),
    places: places,
    busNetwork: bus,
    mrt: fakeMrtRepository(),
    busArrivals: arrivals,
  );

  testWidgets('no journey card, and no bus data load, until both ends exist', (
    tester,
  ) async {
    await pumpApp(tester, gpsApp());
    expect(find.byKey(const Key('journey-card')), findsNothing);
    expect(bus.loads, 0);
  });

  testWidgets('the journey card unfolds inside one MotionSize', (tester) async {
    await pumpApp(tester, gpsApp());
    await searchAndPick(tester, destinationField, 'VivoCity', 'VIVOCITY');
    await tester.pump();
    expect(
      find.ancestor(
        of: find.byKey(const Key('journey-card')),
        matching: find.byType(MotionSize),
      ),
      findsOneWidget,
    );
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

    // Walks are labelled as estimates. Live arrivals (M4) have their own
    // tests in test/features/bus_arrival/.
    expect(find.textContaining('min walk (est.)'), findsWidgets);
    expect(inCard(JourneyCard.estimateNote), findsOneWidget);
    expect(find.byKey(const Key('arrivals-footer')), findsOneWidget);
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
    // No displayed bus option → no arrivals requested or shown.
    expect(find.byKey(const Key('arrivals-footer')), findsNothing);
    expect(arrivals.totalCalls, 0);
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
    bus.failure = const StaticDataUnavailable(StaticDataset.busRoutes);
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

  group('MRT "none within …" text follows the configured maximum', () {
    void addUbin() => places.results['pulau ubin'] = [
      fakePlace(
        'PULAU UBIN JETTY',
        lat: 1.4040,
        lng: 103.9600,
        type: PlaceType.poi,
      ),
    ];

    // Pulau Ubin Jetty is ~5.8 km from the nearest fake exit (Tampines).
    for (final (meters, shown) in [
      (null, '1.5 km'), // the default, JourneyConfig.mrtMaxDistanceMeters
      (2500.0, '2.5 km'),
      (800.0, '800 m'),
    ]) {
      testWidgets('maximum ${meters ?? 'default'} → "$shown"', (tester) async {
        expect(JourneyConfig.mrtMaxDistanceMeters, 1500);
        addUbin();
        await pumpApp(tester, gpsApp(mrtMaxDistanceMeters: meters));
        await searchAndPick(
          tester,
          destinationField,
          'Pulau Ubin',
          'PULAU UBIN JETTY',
        );
        expect(
          textOf(tester, 'journey-mrt-destination'),
          'Near your destination: none within about $shown',
        );
        if (meters != null) {
          expect(find.textContaining('1.5 km'), findsNothing);
        }
      });
    }

    testWidgets('the lookup and the text use the same maximum', (tester) async {
      // The GPS origin is ~31 m from the fake Bishan exit, so a 20 m maximum
      // must hide it as well as change the text.
      await pumpApp(tester, gpsApp(mrtMaxDistanceMeters: 20));
      await searchAndPick(tester, destinationField, 'VivoCity', 'VIVOCITY');
      expect(
        textOf(tester, 'journey-mrt-origin'),
        'Nearest MRT: none within about 20 m',
      );
      expect(find.textContaining('BISHAN MRT STATION'), findsNothing);
    });
  });

  testWidgets('a failed bus data load is held: changing the destination does '
      'not reload it; only Retry does', (tester) async {
    bus.failure = const StaticDataUnavailable(StaticDataset.busRoutes);
    await pumpApp(tester, gpsApp());
    await searchAndPick(tester, destinationField, 'VivoCity', 'VIVOCITY');
    expect(inCard('Bus data is unavailable right now.'), findsOneWidget);
    expect(bus.loads, 1);

    bus.failure = null;
    await tester.tap(find.byKey(const Key('change-destination')));
    await tester.pump();
    await searchAndPick(tester, destinationField, 'ION Orchard', 'ION ORCHARD');
    expect(inCard('Bus data is unavailable right now.'), findsOneWidget);
    expect(bus.loads, 1);

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('journey-card')),
        matching: find.text('Retry'),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(inCard('Bus data is unavailable right now.'), findsNothing);
    expect(
      inKey('journey-suggested', 'Take Bus F30 toward VivoCity (fake)'),
      findsOneWidget,
    );
    expect(bus.loads, 2);
  });
  testWidgets('alternatives show their bus and live times; steps open on '
      'demand', (tester) async {
    await pumpApp(tester, gpsApp());
    await searchAndPick(tester, destinationField, 'VivoCity', 'VIVOCITY');
    await tester.pump();
    await tester.pump();

    const alt = 'journey-alternative-1';
    Finder inAlt(Finder f) =>
        find.descendant(of: find.byKey(const Key(alt)), matching: f);
    expect(inKey(alt, 'Take Bus F10 toward VivoCity (fake)'), findsOneWidget);
    // Live times stay in the collapsed summary (whatever their load state),
    // with the stop they belong to: an alternative may board elsewhere.
    expect(inAlt(find.byKey(const Key('arrivals-BSH1-F10'))), findsOneWidget);
    expect(inAlt(find.textContaining('to Bus Stop BSH1')), findsOneWidget);
    expect(inAlt(find.textContaining('Alight at')), findsNothing);
    expect(inAlt(find.textContaining('to destination')), findsNothing);

    await tester.tap(inKey(alt, 'Show steps'));
    await tester.pump();
    expect(inAlt(find.textContaining('to Bus Stop BSH1')), findsOneWidget);
    expect(
      inAlt(find.text('Alight at VIV1 — VivoCity (fake)')),
      findsOneWidget,
    );
    expect(inKey(alt, 'Hide steps'), findsOneWidget);

    await tester.tap(inKey(alt, 'Hide steps'));
    await tester.pump();
    expect(inAlt(find.textContaining('to Bus Stop BSH1')), findsOneWidget);
    expect(inAlt(find.textContaining('Alight at')), findsNothing);

    // The suggestion is always open and has no toggle.
    expect(inKey('journey-suggested', 'Show steps'), findsNothing);
    expect(inKey('journey-suggested', 'Hide steps'), findsNothing);
  });

  testWidgets('the steps toggle tells screen readers which bus it opens', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpApp(tester, gpsApp());
    await searchAndPick(tester, destinationField, 'VivoCity', 'VIVOCITY');
    await tester.pump();
    await tester.pump();

    expect(find.bySemanticsLabel('Show steps for Bus F10'), findsOneWidget);
    await tester.tap(inKey('journey-alternative-1', 'Show steps'));
    await tester.pump();
    expect(find.bySemanticsLabel('Hide steps for Bus F10'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('journey section titles are headings', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpApp(tester, gpsApp());
    await searchAndPick(tester, destinationField, 'VivoCity', 'VIVOCITY');
    await tester.pump();
    for (final title in [
      'Suggested journey',
      'Alternatives',
      'MRT alternative',
    ]) {
      expect(
        tester.getSemantics(find.text(title)),
        isSemantics(isHeader: true, label: title),
        reason: title,
      );
    }
    semantics.dispose();
  });

  testWidgets('the MRT Retry says what it retries', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpApp(tester, gpsApp(mrtFails: true));
    await searchAndPick(tester, destinationField, 'VivoCity', 'VIVOCITY');
    expect(
      find.bySemanticsLabel('Retry finding the nearest MRT'),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('each option leads with a service badge', (tester) async {
    await pumpApp(tester, gpsApp());
    await searchAndPick(tester, destinationField, 'VivoCity', 'VIVOCITY');
    await tester.pump();
    await tester.pump();
    // The badge is the service number on its own.
    expect(inKey('journey-suggested', 'F20'), findsOneWidget);
    expect(inKey('journey-alternative-1', 'F10'), findsOneWidget);
  });
  testWidgets('only an option with a heading has a gap above its summary', (
    tester,
  ) async {
    await pumpApp(tester, gpsApp());
    await searchAndPick(tester, destinationField, 'VivoCity', 'VIVOCITY');
    await tester.pump();
    await tester.pump();
    double top(Finder f) => tester.getTopLeft(f).dy;
    Finder summary(String option) => find.descendant(
      of: find.byKey(Key(option)),
      matching: find.textContaining('Take Bus'),
    );
    // An alternative has no heading: its summary starts right under the
    // option's 8 px top padding.
    expect(
      top(summary('journey-alternative-1')) -
          top(find.byKey(const Key('journey-alternative-1'))),
      8,
    );
    // The suggestion keeps 4 px between "Suggested" and its summary.
    expect(
      top(summary('journey-suggested')) -
          tester.getBottomLeft(inKey('journey-suggested', 'Suggested')).dy,
      4,
    );
  });
  testWidgets('dark theme, 2× text, 320 dp: the whole journey renders '
      'without overflow, with one MotionSize per animated card', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 8000);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await tester.pumpWidget(gpsApp());
    await tester.pump();
    await searchAndPick(tester, destinationField, 'VivoCity', 'VIVOCITY');
    await tester.pump();
    await tester.pump();
    final show = inKey('journey-alternative-1', 'Show steps');
    await tester.ensureVisible(show);
    await tester.tap(show);
    await tester.pump();

    expect(tester.takeException(), isNull); // no RenderFlex overflow
    expect(find.byKey(const Key('journey-suggested')), findsOneWidget);
    expect(find.byType(MotionSize), findsNWidgets(2)); // route + journey
    expect(
      find.descendant(
        of: find.byType(MotionSize),
        matching: find.byType(MotionSize),
      ),
      findsNothing,
    );
  });

  group('selecting an option (P2-M3)', () {
    testWidgets('the suggestion is selected first; one control per other '
        'option', (tester) async {
      await pumpApp(tester, gpsApp());
      await searchAndPick(tester, destinationField, 'VivoCity', 'VIVOCITY');
      expect(find.byKey(const Key('selected-option-F20')), findsOneWidget);
      expect(find.byKey(const Key('select-option-F10')), findsOneWidget);
      expect(find.byKey(const Key('select-option-F30')), findsOneWidget);
      expect(find.byKey(const Key('select-option-F20')), findsNothing);
    });

    testWidgets('select F10, then back to F20; "Suggested" and the order '
        'never change', (tester) async {
      await pumpApp(tester, gpsApp());
      await searchAndPick(tester, destinationField, 'VivoCity', 'VIVOCITY');
      await select(tester, 'F10');
      expect(find.byKey(const Key('selected-option-F10')), findsOneWidget);
      expect(find.byKey(const Key('selected-option-F20')), findsNothing);
      expect(find.byKey(const Key('select-option-F20')), findsOneWidget);
      expect(
        inKey('journey-suggested', 'Take Bus F20 toward VivoCity (fake)'),
        findsOneWidget,
      );
      expect(
        inKey('journey-alternative-1', 'Take Bus F10 toward VivoCity (fake)'),
        findsOneWidget,
      );
      expect(
        inKey('journey-alternative-2', 'Take Bus F30 toward VivoCity (fake)'),
        findsOneWidget,
      );
      await select(tester, 'F20');
      expect(find.byKey(const Key('selected-option-F20')), findsOneWidget);
      expect(find.byKey(const Key('select-option-F10')), findsOneWidget);
    });

    testWidgets('selecting never re-plans, reloads buses or touches '
        'arrivals', (tester) async {
      await pumpApp(tester, gpsApp());
      await searchAndPick(tester, destinationField, 'VivoCity', 'VIVOCITY');
      await tester.pump();
      final c = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('journey-card'))),
      );
      final plan = c.read(journeyPlanProvider).value;
      final journeyArrivals = c.read(journeyArrivalsProvider).value;
      expect(journeyArrivals, isNotNull);
      final calls = arrivals.totalCalls;
      await select(tester, 'F10');
      await select(tester, 'F30');
      expect(identical(c.read(journeyPlanProvider).value, plan), isTrue);
      expect(
        identical(c.read(journeyArrivalsProvider).value, journeyArrivals),
        isTrue,
      );
      expect(arrivals.totalCalls, calls);
      expect(bus.loads, 1);
    });

    testWidgets('a new journey starts at its suggestion (no stale index)', (
      tester,
    ) async {
      await pumpApp(tester, gpsApp());
      await searchAndPick(tester, destinationField, 'VivoCity', 'VIVOCITY');
      await select(tester, 'F10');
      await tester.tap(find.byKey(const Key('change-destination')));
      await tester.pump();
      // One option only: no select control at all.
      await searchAndPick(
        tester,
        destinationField,
        'ION Orchard',
        'ION ORCHARD',
      );
      expect(find.byKey(const Key('select-option-F30')), findsNothing);
      expect(find.byKey(const Key('selected-option-F30')), findsNothing);
      await tester.tap(find.byKey(const Key('change-destination')));
      await tester.pump();
      // A new plan object for the same trip: back at its suggestion.
      await searchAndPick(tester, destinationField, 'VivoCity', 'VIVOCITY');
      expect(find.byKey(const Key('selected-option-F20')), findsOneWidget);
      expect(find.byKey(const Key('selected-option-F10')), findsNothing);
    });

    testWidgets('"Refresh arrivals" keeps the selection', (tester) async {
      await pumpApp(tester, gpsApp());
      await searchAndPick(tester, destinationField, 'VivoCity', 'VIVOCITY');
      await select(tester, 'F10');
      await tester.tap(find.byKey(const Key('arrivals-refresh')));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('selected-option-F10')), findsOneWidget);
    });

    testWidgets('spoken labels name the bus; the mark is selected', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, gpsApp());
      await searchAndPick(tester, destinationField, 'VivoCity', 'VIVOCITY');
      expect(find.bySemanticsLabel('Select Bus F10'), findsOneWidget);
      expect(find.bySemanticsLabel('Select Bus F30'), findsOneWidget);
      // The default selection is not something the user did: it is not
      // announced (#67).
      expect(
        tester.getSemantics(find.byKey(const Key('selected-option-F20'))),
        isSemantics(
          label: 'Bus F20 selected',
          isSelected: true,
          isLiveRegion: false,
        ),
      );
      await select(tester, 'F10');
      // Selecting removes the focused button, so the mark announces itself.
      expect(
        tester.getSemantics(find.byKey(const Key('selected-option-F10'))),
        isSemantics(
          label: 'Bus F10 selected',
          isSelected: true,
          isLiveRegion: true,
        ),
      );
      await select(tester, 'F20');
      expect(
        tester.getSemantics(find.byKey(const Key('selected-option-F20'))),
        isSemantics(isLiveRegion: true),
      );
      // A new plan's default is quiet again, though the suggestion's state
      // is kept across plans.
      await tester.tap(find.byKey(const Key('change-destination')));
      await tester.pump();
      await searchAndPick(tester, destinationField, 'VivoCity', 'VIVOCITY');
      expect(
        tester.getSemantics(find.byKey(const Key('selected-option-F20'))),
        isSemantics(isSelected: true, isLiveRegion: false),
      );
      handle.dispose();
    });

    testWidgets('2× text at 360 dp: no overflow', (tester) async {
      tester.view.physicalSize = const Size(360, 6000);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(gpsApp());
      await tester.pump();
      await searchAndPick(tester, destinationField, 'VivoCity', 'VIVOCITY');
      expect(find.byKey(const Key('select-option-F10')), findsOneWidget);
      expect(tester.takeException(), isNull);
      // The widest row: an alternative selected, with its steps expanded.
      await select(tester, 'F10');
      final showSteps = find.descendant(
        of: find.byKey(const Key('journey-alternative-1')),
        matching: find.text('Show steps'),
      );
      await tester.ensureVisible(showSteps);
      await tester.tap(showSteps);
      await tester.pump();
      expect(find.byKey(const Key('selected-option-F10')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('journey-alternative-1')),
          matching: find.text('Hide steps'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  // A control that removes itself when pressed leaves focus where it was, not
  // at the top of the page (#56).
  group('focus after a Retry or Select', () {
    bool focusedAt(WidgetTester tester, Finder finder) =>
        Focus.maybeOf(
          tester.element(finder),
          createDependency: false,
        )?.hasPrimaryFocus ??
        false;

    testWidgets('"Retry finding a bus" → the "Suggested journey" heading', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      bus.failure = const StaticDataUnavailable(StaticDataset.busRoutes);
      await pumpApp(tester, gpsApp());
      await searchAndPick(tester, destinationField, 'VivoCity', 'VIVOCITY');
      bus.failure = null;
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('journey-card')),
          matching: find.text('Retry'),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('journey-suggested')), findsOneWidget);
      expect(focusedAt(tester, inCard('Suggested journey')), isTrue);
      expect(
        tester.getSemantics(inCard('Suggested journey')),
        isSemantics(isHeader: true, isFocused: true),
      );
      semantics.dispose();
    });

    testWidgets('the MRT Retry → the "MRT alternative" heading', (
      tester,
    ) async {
      await pumpApp(tester, gpsApp(mrtFails: true));
      await searchAndPick(tester, destinationField, 'VivoCity', 'VIVOCITY');
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('journey-mrt')),
          matching: find.text('Retry'),
        ),
      );
      await tester.pump();
      expect(focusedAt(tester, inCard('MRT alternative')), isTrue);
    });

    testWidgets('a live-arrivals Retry → its option\'s "Take Bus" line', (
      tester,
    ) async {
      arrivals.failure = const NetworkUnavailable();
      await pumpApp(tester, gpsApp());
      await searchAndPick(tester, destinationField, 'VivoCity', 'VIVOCITY');
      await tester.pump();
      arrivals.failure = null;
      final retry = find.descendant(
        of: find.byKey(const Key('journey-alternative-1')),
        matching: find.text('Retry'),
      );
      await tester.ensureVisible(retry);
      await tester.pump();
      await tester.tap(retry);
      await tester.pump();
      expect(
        focusedAt(
          tester,
          inKey('journey-alternative-1', 'Take Bus F10 toward VivoCity (fake)'),
        ),
        isTrue,
      );
    });

    testWidgets('Select → the new "Selected" mark', (tester) async {
      await pumpApp(tester, gpsApp());
      await searchAndPick(tester, destinationField, 'VivoCity', 'VIVOCITY');
      await select(tester, 'F10');
      expect(
        focusedAt(tester, inKey('journey-alternative-1', 'Selected')),
        isTrue,
      );
      await select(tester, 'F20');
      expect(focusedAt(tester, inKey('journey-suggested', 'Selected')), isTrue);
    });
  });
}
