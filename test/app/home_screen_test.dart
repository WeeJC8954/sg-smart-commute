// UI polish follow-ups: the home screen at the real card-resize duration, and
// what scrolling far down does to the top section (diagnostic D3). Every
// external provider is a fake (integration_test/fakes/).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/core/config/app_config.dart';
import 'package:sg_smart_commute/core/geo/geo.dart';
import 'package:sg_smart_commute/core/location/location_service.dart';
import 'package:sg_smart_commute/core/ui/motion.dart';
import 'package:sg_smart_commute/features/journey/data/mrt_asset.dart';
import 'package:sg_smart_commute/features/journey/data/mrt_asset_repository.dart';

import '../../integration_test/fakes/fake_bus_arrival_repository.dart';
import '../../integration_test/fakes/fake_bus_network.dart';
import '../../integration_test/fakes/fake_environment_repository.dart';
import '../../integration_test/fakes/fake_location_service.dart';
import '../../integration_test/fakes/fake_place_search_repository.dart';
import '../../integration_test/fakes/fake_route_geometry.dart';
import '../../integration_test/fakes/test_app.dart';

const bishan = LatLng(1.3508, 103.8485);
const destinationField = Key('destination-field');
const journeyCard = Key('journey-card');
const alternative = Key('journey-alternative-1');

void main() {
  late FakeBusNetworkRepository bus;
  late FakeBusArrivalRepository arrivals;
  late FakeRouteGeometryRepository geometry;
  late Completer<void> mrtGate;

  setUp(() {
    bus = FakeBusNetworkRepository();
    arrivals = FakeBusArrivalRepository();
    geometry = FakeRouteGeometryRepository();
    mrtGate = Completer<void>()..complete(); // open unless a test holds it
  });

  /// The real app at Bishan by GPS. [motion] is the card-resize duration;
  /// buildTestApp's default is zero.
  Widget app({Duration motion = Duration.zero}) => buildTestApp(
    location: FakeLocationService(
      access: LocationAccess.granted,
      position: bishan,
    ),
    environment: FakeEnvironmentRepository(),
    places: FakePlaceSearchRepository(),
    busNetwork: bus,
    busArrivals: arrivals,
    routeGeometry: geometry,
    // The fake MRT asset, behind a gate the motion tests can hold.
    mrt: MrtAssetRepository(
      load: () async {
        await mrtGate.future;
        return jsonEncode({'stations': encodeMrtStations(fakeMrtStations)});
      },
    ),
    motionDuration: motion,
  );

  /// Types VivoCity and picks it. The route card resizes when the results
  /// appear, so [settle] lets that finish before the tap.
  Future<void> pickVivoCity(
    WidgetTester tester, {
    Duration settle = Duration.zero,
  }) async {
    await tester.enterText(find.byKey(destinationField), 'VivoCity');
    await tester.pump(pastSearchDebounce);
    await tester.pump();
    await tester.pump(settle);
    await tester.tap(find.text('VIVOCITY'));
    await tester.pump();
  }

  Finder inAlternative(String text) =>
      find.descendant(of: find.byKey(alternative), matching: find.text(text));

  group('motion at the real duration (AppMotion.resize)', () {
    /// The journey card's height as the user sees it (its MotionSize) and
    /// its full height.
    double shown(WidgetTester tester) => tester
        .getSize(
          find.ancestor(
            of: find.byKey(journeyCard),
            matching: find.byType(MotionSize),
          ),
        )
        .height;
    double full(WidgetTester tester) =>
        tester.getSize(find.byKey(journeyCard)).height;

    Future<void> pumpTall(WidgetTester tester, Widget widget) async {
      tester.view.physicalSize = const Size(1080, 5000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(widget);
      await tester.pump();
    }

    /// Holds every journey source, so the card's entrance is one change
    /// (nothing → its loading rows). Data landing on the very next frame
    /// would make AnimatedSize jump instead (docs/assumptions.md, "Motion").
    void holdJourneyData() {
      bus.hold();
      arrivals
        ..hold('BSH1')
        ..hold('BSH2');
      mrtGate = Completer<void>();
    }

    void releaseJourneyData() {
      bus.release();
      mrtGate.complete();
      arrivals
        ..release('BSH1')
        ..release('BSH2');
    }

    testWidgets('the journey card unfolds over AppMotion.resize, then is '
        'usable', (tester) async {
      holdJourneyData();
      await pumpTall(tester, app(motion: AppMotion.resize));
      await pickVivoCity(tester, settle: AppMotion.resize);

      await tester.pump(AppMotion.resize ~/ 2);
      expect(shown(tester), greaterThan(0));
      expect(shown(tester), lessThan(full(tester))); // still unfolding
      await tester.pump(AppMotion.resize ~/ 2);
      expect(shown(tester), full(tester));

      releaseJourneyData();
      await tester.pump();
      await tester.pump();
      await tester.pump(AppMotion.resize);
      expect(shown(tester), full(tester));

      await tester.tap(inAlternative('Show steps'));
      await tester.pump();
      await tester.pump(AppMotion.resize);
      expect(inAlternative('Hide steps'), findsOneWidget);
      await tester.tap(find.byKey(const Key('select-option-F10')));
      await tester.pump();
      await tester.pump(AppMotion.resize);
      expect(find.byKey(const Key('selected-option-F10')), findsOneWidget);
      expect(shown(tester), full(tester));
      expect(tester.takeException(), isNull);
    });

    testWidgets('reduce motion: the journey card lands in one frame', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      holdJourneyData();
      await pumpTall(tester, app(motion: AppMotion.resize));
      await pickVivoCity(tester);

      expect(shown(tester), greaterThan(0));
      expect(shown(tester), full(tester));
      releaseJourneyData();
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('"Hide steps" right after "Show steps" reverses from the '
        'current height, with no jump', (tester) async {
      await pumpTall(tester, app(motion: AppMotion.resize));
      await pickVivoCity(tester, settle: AppMotion.resize);
      // Let the data land and the card settle: one pump is one frame, and a
      // change on the frame after another one jumps instead of animating.
      for (var i = 0; i < 4; i++) {
        await tester.pump(AppMotion.resize);
      }
      final closed = shown(tester);
      expect(closed, full(tester)); // settled

      await tester.tap(inAlternative('Show steps'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final opening = shown(tester);
      expect(opening, greaterThan(closed));
      expect(opening, lessThan(full(tester))); // still opening

      await tester.tap(inAlternative('Hide steps'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(shown(tester), lessThanOrEqualTo(opening)); // box: no jump open
      expect(shown(tester), greaterThan(closed)); // box: no jump shut
      await tester.pump(AppMotion.resize);
      expect(shown(tester), closed);
      expect(tester.takeException(), isNull);
    });
  });

  group('scrolling to the bottom and back (diagnostic D3)', () {
    for (final scale in [1.0, 2.0]) {
      testWidgets('360 × 780 dp at $scale× text: what the top section '
          'keeps', (tester) async {
        tester.view.physicalSize = const Size(360, 780);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(app());
        await tester.pump();
        await pickVivoCity(tester);
        await tester.pump();

        Future<void> tapVisible(Finder finder) async {
          await tester.ensureVisible(finder);
          await tester.pump();
          await tester.tap(finder);
          await tester.pump();
          await tester.pump();
        }

        // The user's own state in the top section: an alternative's steps
        // open, that alternative selected, the map open and panned.
        await tapVisible(inAlternative('Show steps'));
        await tapVisible(find.byKey(const Key('select-option-F10')));
        await tapVisible(find.byKey(const Key('show-map')));
        await tester.ensureVisible(find.byType(FlutterMap));
        await tester.pump();
        MapCamera camera() =>
            MapCamera.of(tester.element(find.byType(MarkerLayer)));
        await tester.timedDrag(
          find.byType(FlutterMap),
          const Offset(-80, 0),
          const Duration(milliseconds: 600),
        );
        await tester.pump(const Duration(seconds: 1));
        final panned = camera().center;
        final map = tester.state(find.byType(FlutterMap));
        final loads = (
          bus: bus.loads,
          arrivals: arrivals.totalCalls,
          geometry: geometry.loads,
        );

        final list = tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position;
        list.jumpTo(list.maxScrollExtent);
        await tester.pump();
        final disposed = find
            .byKey(journeyCard, skipOffstage: false)
            .evaluate()
            .isEmpty;
        list.jumpTo(0);
        await tester.pump();
        await tester.pump();

        // Must hold either way: what the app owns survives, and nothing is
        // fetched again (once-per-session loads, one arrivals request per
        // shown stop).
        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const Key('selected-option-F10'), skipOffstage: false),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('map-card'), skipOffstage: false),
          findsOneWidget,
        );
        expect((
          bus: bus.loads,
          arrivals: arrivals.totalCalls,
          geometry: geometry.loads,
        ), loads);

        // What the widgets kept: observed, not required. D3: no keep-alive
        // change without a separate decision (docs/assumptions.md, "Home
        // list scrolling").
        await tester.ensureVisible(find.byType(FlutterMap));
        await tester.pump();
        final stepsOpen = find
            .text('Hide steps', skipOffstage: false)
            .evaluate()
            .isNotEmpty;
        debugPrint(
          'D3 $scale× text: top section disposed at the bottom: $disposed; '
          'steps still open: $stepsOpen; map kept its state: '
          '${identical(map, tester.state(find.byType(FlutterMap)))}; '
          'camera kept the pan: ${camera().center == panned}',
        );
      });
    }
  });
}
