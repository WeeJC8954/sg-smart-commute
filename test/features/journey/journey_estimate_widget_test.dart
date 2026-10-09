// E2 estimated trip time on the journey card (plan §6, §8 T2): the trip line
// below the live arrivals on every direct-bus option, the ride on the bus
// step, the footer, semantics, large text and all five palettes. Expected
// values come from the plan's §3.4 table for the fake network.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/core/errors/app_failure.dart';
import 'package:sg_smart_commute/core/geo/geo.dart';
import 'package:sg_smart_commute/core/location/location_service.dart';
import 'package:sg_smart_commute/features/appearance/domain/app_palette.dart';
import 'package:sg_smart_commute/features/journey/domain/bus_network.dart';
import 'package:sg_smart_commute/features/journey/presentation/journey_card.dart';
import 'package:sg_smart_commute/features/places/domain/place.dart';

import '../../../integration_test/fakes/fake_bus_arrival_repository.dart';
import '../../../integration_test/fakes/fake_bus_network.dart';
import '../../../integration_test/fakes/fake_environment_repository.dart';
import '../../../integration_test/fakes/fake_location_service.dart';
import '../../../integration_test/fakes/fake_place_search_repository.dart';
import '../../../integration_test/fakes/test_app.dart';

const bishan = LatLng(1.3508, 103.8485);
const destinationField = Key('destination-field');
const originField = Key('manual-origin-field');

Key tripKey(String board, String service) =>
    Key('trip-estimate-$board-$service');
Key rideKey(String board, String service) => Key('ride-step-$board-$service');

Finder inKey(Key key, Finder f) =>
    find.descendant(of: find.byKey(key), matching: f);

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

Future<void> showSteps(WidgetTester tester, String option) async {
  final button = inKey(Key(option), find.text('Show steps'));
  await tester.ensureVisible(button);
  await tester.pump();
  await tester.tap(button);
  await tester.pump();
}

/// The fake stops with other services (the fake network's own stops).
BusNetwork networkWith(List<BusService> services) => BusNetwork(
  stops: fakeBusNetwork().stops,
  services: {for (final s in services) s.number: s},
);

BusService svc(String number, List<List<String>> directions) =>
    BusService(number: number, name: 'Fake $number', directions: directions);

double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  late FakeBusNetworkRepository bus;
  late FakePlaceSearchRepository places;
  late FakeBusArrivalRepository arrivals;

  setUp(() {
    bus = FakeBusNetworkRepository();
    places = FakePlaceSearchRepository();
    arrivals = FakeBusArrivalRepository();
  });

  Widget app({
    FakeBusNetworkRepository? network,
    AppPalette palette = AppPalette.teal,
    LocationAccess access = LocationAccess.granted,
  }) => buildTestApp(
    location: FakeLocationService(access: access, position: bishan),
    environment: FakeEnvironmentRepository(),
    places: places,
    busNetwork: network ?? bus,
    mrt: fakeMrtRepository(),
    busArrivals: arrivals,
    palette: palette,
  );

  Future<void> pumpApp(WidgetTester tester, Widget widget) async {
    tester.view.physicalSize = const Size(1080, 5000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(widget);
    await tester.pump();
  }

  Future<void> toVivoCity(WidgetTester tester, [Widget? widget]) async {
    await pumpApp(tester, widget ?? app());
    await searchAndPick(tester, destinationField, 'VivoCity', 'VIVOCITY');
    await tester.pump();
    await tester.pump();
  }

  testWidgets('every direct-bus option shows its trip line, collapsed '
      'alternatives too', (tester) async {
    await toVivoCity(tester);
    for (final (option, board, service) in [
      ('journey-suggested', 'BSH2', 'F20'),
      ('journey-alternative-1', 'BSH1', 'F10'),
      ('journey-alternative-2', 'BSH1', 'F30'),
    ]) {
      expect(
        inKey(Key(option), find.byKey(tripKey(board, service))),
        findsOneWidget,
        reason: option,
      );
    }
    // F20 2 + 31 + 1, F10 1 + 32 + 1, F30 1 + 30 + 1: all round up to 35.
    expect(find.text('About 35 min · excl. waiting'), findsNWidgets(3));
    expect(JourneyCard.tripLine(35), 'About 35 min · excl. waiting');
  });

  testWidgets('the bus step adds the estimated ride; the alternatives differ', (
    tester,
  ) async {
    await toVivoCity(tester);
    Finder ride(String board, String service, String text) =>
        inKey(rideKey(board, service), find.text(text));
    // The stop count stays its own text, exactly as before E2.
    expect(ride('BSH2', 'F20', '2 stops'), findsOneWidget);
    expect(ride('BSH2', 'F20', '· ~31 min ride (est.)'), findsOneWidget);
    expect(JourneyCard.rideDetail(31), '· ~31 min ride (est.)');
    // Collapsed alternatives show no ride step until "Show steps".
    expect(find.byKey(rideKey('BSH1', 'F10')), findsNothing);
    await showSteps(tester, 'journey-alternative-1');
    await showSteps(tester, 'journey-alternative-2');
    expect(ride('BSH1', 'F10', '3 stops'), findsOneWidget);
    expect(ride('BSH1', 'F10', '· ~32 min ride (est.)'), findsOneWidget);
    expect(ride('BSH1', 'F30', '3 stops'), findsOneWidget);
    expect(ride('BSH1', 'F30', '· ~30 min ride (est.)'), findsOneWidget);
  });

  testWidgets('options with different estimates show different totals', (
    tester,
  ) async {
    // G1: BSH2 → VIV1, 1 stop (2 + 29 + 1 → 35). G2: BSH1 → TPH1 → VIV1,
    // 2 stops via Tampines (1 + 77 + 1 → 80). G1 is still Suggested (4.5 vs 5).
    final spread = FakeBusNetworkRepository(
      network: networkWith([
        svc('G1', [
          ['BSH2', 'VIV1'],
        ]),
        svc('G2', [
          ['BSH1', 'TPH1', 'VIV1'],
        ]),
      ]),
    );
    await toVivoCity(tester, app(network: spread));
    expect(
      inKey(
        const Key('journey-suggested'),
        find.text('Take Bus G1 toward VivoCity (fake)'),
      ),
      findsOneWidget,
    );
    expect(
      inKey(tripKey('BSH2', 'G1'), find.text('About 35 min · excl. waiting')),
      findsOneWidget,
    );
    expect(
      inKey(tripKey('BSH1', 'G2'), find.text('About 80 min · excl. waiting')),
      findsOneWidget,
    );
    await showSteps(tester, 'journey-alternative-1');
    expect(
      inKey(rideKey('BSH1', 'G2'), find.text('· ~77 min ride (est.)')),
      findsOneWidget,
    );
  });

  group('below the live arrivals, whatever their state', () {
    testWidgets('title, then arrivals, then the trip line', (tester) async {
      await toVivoCity(tester);
      double top(Finder f) => tester.getTopLeft(f).dy;
      final title = inKey(
        const Key('journey-suggested'),
        find.text('Take Bus F20 toward VivoCity (fake)'),
      );
      final live = find.byKey(const Key('arrivals-BSH2-F20'));
      final trip = find.byKey(tripKey('BSH2', 'F20'));
      expect(top(title), lessThan(top(live)));
      expect(top(live), lessThan(top(trip)));
      expect(tester.getBottomLeft(live).dy, lessThanOrEqualTo(top(trip)));
    });

    testWidgets('while arrivals are still loading', (tester) async {
      arrivals.hold('BSH2');
      await toVivoCity(tester);
      expect(find.byKey(tripKey('BSH2', 'F20')), findsOneWidget);
      arrivals.release('BSH2');
      await tester.pump();
      await tester.pump();
      expect(find.byKey(tripKey('BSH2', 'F20')), findsOneWidget);
    });

    testWidgets('when arrivals fail (Retry shown)', (tester) async {
      arrivals.failure = const NetworkUnavailable();
      await toVivoCity(tester);
      expect(
        inKey(const Key('journey-suggested'), find.text('Retry')),
        findsOneWidget,
      );
      expect(
        inKey(
          tripKey('BSH2', 'F20'),
          find.text('About 35 min · excl. waiting'),
        ),
        findsOneWidget,
      );
    });
  });

  testWidgets('screen readers hear the trip and the ride in words', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await toVivoCity(tester);
    expect(
      tester.getSemantics(find.byKey(tripKey('BSH2', 'F20'))),
      isSemantics(
        label: 'Estimated trip, about 35 minutes, not including waiting',
        isHeader: false,
        isLiveRegion: false,
      ),
    );
    expect(
      tester.getSemantics(find.byKey(rideKey('BSH2', 'F20'))),
      isSemantics(label: '2 stops, about 31 minutes on the bus, estimated'),
    );
    expect(
      JourneyCard.tripSemantics(35),
      'Estimated trip, about 35 minutes, not including waiting',
    );
    expect(
      JourneyCard.rideSemantics(1, 17),
      '1 stop, about 17 minutes on the bus, estimated',
    );
    // The walking steps read as before.
    expect(
      find.bySemanticsLabel(
        RegExp(r'~\d+ min walk \(est\.\) to Bus Stop BSH2'),
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });

  group('the footer', () {
    const note =
        'Trip times are rough estimates based on scheduled early/late bus '
        'timings. They exclude waiting and live traffic conditions.';

    testWidgets('with a direct bus: the walking note, then the E2 note', (
      tester,
    ) async {
      await toVivoCity(tester);
      expect(JourneyCard.tripEstimateNote, note);
      expect(find.text(note), findsOneWidget);
      expect(find.text(JourneyCard.estimateNote), findsOneWidget);
      expect(
        tester.getTopLeft(find.text(JourneyCard.estimateNote)).dy,
        lessThan(tester.getTopLeft(find.text(note)).dy),
      );
    });

    testWidgets('walk-only: no trip line, no E2 note, no bus data', (
      tester,
    ) async {
      places.results['bishan park'] = [
        fakePlace('BISHAN PARK EDGE', lat: 1.3520, lng: 103.8500),
      ];
      await pumpApp(tester, app());
      await searchAndPick(
        tester,
        destinationField,
        'Bishan Park',
        'BISHAN PARK EDGE',
      );
      expect(find.byKey(const Key('journey-walk-only')), findsOneWidget);
      expect(find.textContaining('excl. waiting'), findsNothing);
      expect(find.text(note), findsNothing);
      expect(find.text(JourneyCard.estimateNote), findsOneWidget);
      expect(bus.loads, 0);
    });

    testWidgets('no direct bus: no trip line, no E2 note', (tester) async {
      await pumpApp(tester, app(access: LocationAccess.denied));
      await searchAndPick(
        tester,
        originField,
        'Tampines Hub',
        'OUR TAMPINES HUB',
      );
      await searchAndPick(tester, destinationField, '238801', 'ION ORCHARD');
      expect(find.byKey(const Key('journey-no-direct')), findsOneWidget);
      expect(find.textContaining('excl. waiting'), findsNothing);
      expect(find.text(note), findsNothing);
    });

    testWidgets('no stop nearby: no trip line, no E2 note', (tester) async {
      places.results['pulau ubin'] = [
        fakePlace(
          'PULAU UBIN JETTY',
          lat: 1.4040,
          lng: 103.9600,
          type: PlaceType.poi,
        ),
      ];
      await pumpApp(tester, app());
      await searchAndPick(
        tester,
        destinationField,
        'Pulau Ubin',
        'PULAU UBIN JETTY',
      );
      expect(find.byKey(const Key('journey-no-stops')), findsOneWidget);
      expect(find.textContaining('excl. waiting'), findsNothing);
      expect(find.text(note), findsNothing);
    });
  });

  testWidgets('a ride the network cannot place: that option has no '
      'estimate; the others keep theirs and nothing moves', (tester) async {
    // F30 runs through a stop code the network does not have.
    final ghost = FakeBusNetworkRepository(
      network: networkWith([
        ...fakeBusNetwork().services.values.where((s) => s.number != 'F30'),
        svc('F30', [
          ['BSH1', 'GHOST', 'ION1', 'MID2', 'VIV1'],
        ]),
      ]),
    );
    await toVivoCity(tester, app(network: ghost));
    expect(
      inKey(
        const Key('journey-suggested'),
        find.text('Take Bus F20 toward VivoCity (fake)'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(tripKey('BSH2', 'F20')), findsOneWidget);
    expect(find.byKey(tripKey('BSH1', 'F10')), findsOneWidget);
    expect(find.byKey(tripKey('BSH1', 'F30')), findsNothing);
    await showSteps(tester, 'journey-alternative-2');
    final alt = find.byKey(const Key('journey-alternative-2'));
    expect(
      inKey(const Key('journey-alternative-2'), find.text('4 stops')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: alt, matching: find.textContaining('min ride')),
      findsNothing,
    );
    expect(find.byKey(rideKey('BSH1', 'F30')), findsNothing);
  });

  for (final width in [360.0, 320.0]) {
    for (final brightness in Brightness.values) {
      testWidgets('2× text at ${width.round()} dp, ${brightness.name}: no '
          'overflow; the trip line wraps inside its option', (tester) async {
        tester.view.physicalSize = Size(width, 9000);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        await tester.pumpWidget(app());
        await tester.pump();
        await searchAndPick(tester, destinationField, 'VivoCity', 'VIVOCITY');
        await tester.pump();
        await showSteps(tester, 'journey-alternative-1');
        expect(tester.takeException(), isNull);
        final trip = find.byKey(tripKey('BSH2', 'F20'));
        final option = find.byKey(const Key('journey-suggested'));
        expect(
          tester.getTopRight(trip).dx,
          lessThanOrEqualTo(tester.getTopRight(option).dx),
        );
        // At 2× the line no longer fits on one row: it wraps, not clips.
        final line = tester.getSize(
          inKey(tripKey('BSH2', 'F20'), find.byType(Text)),
        );
        // One 28 px line is about 40 px tall; two or more exceed 56 px.
        expect(line.height, greaterThan(2 * 14 * 2));
      });
    }
  }

  for (final palette in AppPalette.values) {
    for (final brightness in Brightness.values) {
      testWidgets('${palette.name} ${brightness.name}: the trip line is in '
          'the scheme\'s onSurfaceVariant, readable on the card', (
        tester,
      ) async {
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        await toVivoCity(tester, app(palette: palette));
        final text = inKey(tripKey('BSH2', 'F20'), find.byType(Text));
        final scheme = Theme.of(tester.element(text)).colorScheme;
        expect(scheme.brightness, brightness);
        expect(tester.widget<Text>(text).style?.color, scheme.onSurfaceVariant);
        final card = tester
            .widget<Material>(
              find
                  .descendant(
                    of: find.byKey(const Key('journey-card')),
                    matching: find.byType(Material),
                  )
                  .first,
            )
            .color!;
        expect(
          contrast(scheme.onSurfaceVariant, card),
          greaterThanOrEqualTo(4.5),
        );
      });
    }
  }
}
