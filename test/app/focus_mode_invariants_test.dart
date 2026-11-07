// E7 T9: a focus highlight mode change only draws or hides the ring. No
// re-plan, refetch, reselection, refit, route-geometry load or tile request;
// no control changes size; no overflow at 360 dp with 2× text; the
// semantics tree is the same with and without the ring.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/app/home_screen.dart';
import 'package:sg_smart_commute/core/geo/geo.dart';
import 'package:sg_smart_commute/core/location/location_service.dart';
import 'package:sg_smart_commute/features/journey/journey_providers.dart';
import 'package:sg_smart_commute/features/map/presentation/journey_map.dart';

import '../../integration_test/fakes/fake_bus_arrival_repository.dart';
import '../../integration_test/fakes/fake_bus_network.dart';
import '../../integration_test/fakes/fake_environment_repository.dart';
import '../../integration_test/fakes/fake_location_service.dart';
import '../../integration_test/fakes/fake_map.dart';
import '../../integration_test/fakes/fake_palette_store.dart';
import '../../integration_test/fakes/fake_place_search_repository.dart';
import '../../integration_test/fakes/fake_route_geometry.dart';
import '../../integration_test/fakes/test_app.dart';

const bishan = LatLng(1.3508, 103.8485);

Finder key(String k) => find.byKey(Key(k));

/// Whether the primary focus is [f] or inside it.
bool focusIn(Finder f) {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  final target = f.evaluate().first;
  var inside = identical(context, target);
  context.visitAncestorElements((e) {
    inside = inside || identical(e, target);
    return !inside;
  });
  return inside;
}

/// Tabs forward until [f] has focus (a real keyboard path).
Future<void> tabTo(WidgetTester tester, Finder f) async {
  for (var i = 0; i < 80; i++) {
    if (focusIn(f)) return;
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.pump();
  }
  fail('Tab never reached $f');
}

void main() {
  late FakeBusNetworkRepository bus;
  late FakeBusArrivalRepository arrivals;
  late FakeRouteGeometryRepository geometry;
  late FakeTileProvider tiles;

  setUp(() {
    bus = FakeBusNetworkRepository();
    arrivals = FakeBusArrivalRepository();
    geometry = FakeRouteGeometryRepository();
    tiles = FakeTileProvider();
  });

  Future<void> tapVisible(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pump();
    await tester.tap(f);
    await tester.pump();
    await tester.pump();
  }

  /// A key event: Flutter's highlight mode becomes traditional.
  Future<void> keyboardMode(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    await tester.pump();
  }

  /// A touch on an empty part of the page: touch mode.
  Future<void> touchMode(WidgetTester tester) async {
    await tester.tapAt(
      tester.getBottomRight(find.byType(HomeScreen)) - const Offset(4, 4),
    );
    await tester.pump();
    await tester.pump();
  }

  /// Bishan by GPS → Bay Mall, F10 selected, the map open.
  Future<void> journey(
    WidgetTester tester, {
    Size size = const Size(1080, 5000),
  }) async {
    tester.view.physicalSize = size;
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
        busArrivals: arrivals,
        routeGeometry: geometry,
        mapTiles: () => tiles,
        paletteStore: FakePaletteStore(),
      ),
    );
    await tester.pump();
    await tester.enterText(key('destination-field'), 'Bay Mall');
    await tester.pump(pastSearchDebounce);
    await tester.pump();
    await tester.tap(find.text('BAY MALL (fake)'));
    await tester.pump();
    await tester.pump();
    await tapVisible(tester, key('select-option-F10'));
    await tapVisible(tester, key('show-map'));
  }

  Object? plan(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(HomeScreen)))
          .read(journeyPlanProvider)
          .value;

  testWidgets('touch ↔ keyboard with the map open: the same map, camera, '
      'tiles, plan, loads and selection', (tester) async {
    await journey(tester);
    final map = tester.state(find.byType(FlutterMap));
    final journeyMap = tester.state(find.byType(JourneyMap));
    MapCamera camera() =>
        MapCamera.of(tester.element(find.byType(MarkerLayer)));
    final center = camera().center;
    final zoom = camera().zoom;
    final requested = tiles.requested.length;
    expect(requested, greaterThan(0), reason: 'the open map has tiles');
    final before = (
      plan: plan(tester),
      bus: bus.loads,
      arrivals: arrivals.totalCalls,
      geometry: geometry.loads,
    );

    for (final change in [keyboardMode, touchMode, keyboardMode]) {
      await change(tester);
      expect(tester.takeException(), isNull);
      expect(identical(map, tester.state(find.byType(FlutterMap))), isTrue);
      expect(
        identical(journeyMap, tester.state(find.byType(JourneyMap))),
        isTrue,
      );
      expect(camera().center, center, reason: '0 refits');
      expect(camera().zoom, zoom);
      expect(tiles.requested.length, requested, reason: '0 tile requests');
      expect(identical(plan(tester), before.plan), isTrue, reason: '0 plans');
      expect(bus.loads, before.bus);
      expect(arrivals.totalCalls, before.arrivals, reason: '0 refetches');
      expect(geometry.loads, before.geometry);
      expect(key('selected-option-F10'), findsOneWidget);
    }
  });

  testWidgets('the ring changes no size: each control is as big focused in '
      'keyboard mode as unfocused', (tester) async {
    await journey(tester);
    final alternative = find.byWidgetPredicate((w) {
      final k = w.key;
      return k is ValueKey<String> && k.value.startsWith('select-option-');
    });
    final controls = [
      key('about-button'),
      key('palette-button'),
      key('refresh-conditions'),
      key('change-origin'),
      key('arrivals-refresh').first,
      alternative.first,
      key('hide-map'),
    ];
    final sizes = [for (final c in controls) tester.getSize(c)];
    for (var i = 0; i < controls.length; i++) {
      await tabTo(tester, controls[i]);
      expect(tester.getSize(controls[i]), sizes[i], reason: '${controls[i]}');
    }
  });

  testWidgets('360 × 780 dp with 2× text: Tab through the page in keyboard '
      'mode with no overflow', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await journey(tester, size: const Size(360, 780));
    for (var i = 0; i < 40; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'Tab $i');
    }
  });

  testWidgets('the semantics tree is the same with and without the ring', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await journey(tester);
    // "Show map" moved focus to "Hide map" (touch mode: no ring).
    String tree() => tester
        .getSemantics(find.byType(HomeScreen))
        .toStringDeep(childOrder: DebugSemanticsDumpOrder.traversalOrder);
    final withoutRing = tree();
    await keyboardMode(tester);
    expect(tree(), withoutRing);
    handle.dispose();
  });
}
