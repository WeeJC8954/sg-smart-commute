// E1 map-state contract: a palette change only recolours. No re-plan,
// refetch, reselection, refit, route-geometry load or tile request; only
// the system brightness switches OneMap Default/Night.
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/app/home_screen.dart';
import 'package:sg_smart_commute/core/config/app_config.dart';
import 'package:sg_smart_commute/core/geo/geo.dart';
import 'package:sg_smart_commute/core/location/location_service.dart';
import 'package:sg_smart_commute/features/appearance/domain/app_palette.dart';
import 'package:sg_smart_commute/features/appearance/presentation/palette_theme.dart';
import 'package:sg_smart_commute/features/journey/journey_providers.dart';
import 'package:sg_smart_commute/features/map/presentation/journey_map.dart';

import '../../../integration_test/fakes/fake_bus_arrival_repository.dart';
import '../../../integration_test/fakes/fake_bus_network.dart';
import '../../../integration_test/fakes/fake_environment_repository.dart';
import '../../../integration_test/fakes/fake_location_service.dart';
import '../../../integration_test/fakes/fake_map.dart';
import '../../../integration_test/fakes/fake_palette_store.dart';
import '../../../integration_test/fakes/fake_place_search_repository.dart';
import '../../../integration_test/fakes/fake_route_geometry.dart';
import '../../../integration_test/fakes/test_app.dart';

const bishan = LatLng(1.3508, 103.8485);

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

  /// Bishan by GPS → VivoCity, the F10 alternative selected.
  Future<void> journey(WidgetTester tester) async {
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
        busArrivals: arrivals,
        routeGeometry: geometry,
        mapTiles: () => tiles,
        paletteStore: FakePaletteStore(),
      ),
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('destination-field')),
      'VivoCity',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    await tester.tap(find.text('VIVOCITY'));
    await tester.pump();
    await tester.pump();
    await tapVisible(tester, find.byKey(const Key('select-option-F10')));
  }

  /// Chooses [p] in the app-bar menu and steps through the cross-fade.
  Future<void> choose(
    WidgetTester tester,
    AppPalette p, {
    void Function(int frame)? eachFrame,
  }) async {
    await tester.tap(find.byKey(const Key('palette-button')));
    await tester.pump();
    await tester.tap(find.byKey(Key('palette-option-${p.id}')).first);
    await tester.pump();
    for (var i = 0; i < 15; i++) {
      await tester.pump(
        const Duration(milliseconds: 20),
      ); // the 200 ms cross-fade
      expect(tester.takeException(), isNull, reason: 'frame $i');
      eachFrame?.call(i);
    }
  }

  Object? plan(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(HomeScreen)))
          .read(journeyPlanProvider)
          .value;

  ({int bus, int arrivals, int geometry}) loads() =>
      (bus: bus.loads, arrivals: arrivals.totalCalls, geometry: geometry.loads);

  MapCamera camera(WidgetTester tester) =>
      MapCamera.of(tester.element(find.byType(MarkerLayer)));
  String template(WidgetTester tester) =>
      tester.widget<TileLayer>(find.byType(TileLayer)).urlTemplate!;
  Color rideColour(WidgetTester tester) => tester
      .widget<PolylineLayer>(find.byKey(const Key('map-ride-line')))
      .polylines
      .single
      .color;

  testWidgets('map closed: no tile or route-geometry request, no re-plan, no '
      'refetch, the selection kept', (tester) async {
    await journey(tester);
    final before = (plan: plan(tester), loads: loads());
    expect(before.plan, isNotNull);
    await choose(tester, AppPalette.rose);
    expect(identical(plan(tester), before.plan), isTrue, reason: '0 new plans');
    expect(loads(), before.loads);
    expect(geometry.loads, 0);
    expect(tiles.requested, isEmpty);
    expect(find.byKey(const Key('selected-option-F10')), findsOneWidget);
  });

  testWidgets('map open and panned: Teal → Rose in light keeps Default, the '
      'map, camera, tiles, plan, loads and selection; dark switches to Night '
      'only by brightness', (tester) async {
    await journey(tester);
    await tapVisible(tester, find.byKey(const Key('show-map')));
    final fitted = camera(tester).center;
    await tester.timedDrag(
      find.byType(FlutterMap),
      const Offset(-80, 0),
      const Duration(milliseconds: 600),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(
      camera(tester).center,
      isNot(fitted),
      reason: 'the pan moved the camera',
    );

    final map = tester.state(find.byType(FlutterMap));
    final journeyMap = tester.state(find.byType(JourneyMap));
    final center = camera(tester).center;
    final zoom = camera(tester).zoom;
    var requested = tiles.requested.length;
    final before = (plan: plan(tester), loads: loads());
    expect(template(tester), BasemapEndpoints.defaultTiles);

    await choose(
      tester,
      AppPalette.rose,
      eachFrame: (_) => expect(template(tester), BasemapEndpoints.defaultTiles),
    );
    expect(identical(map, tester.state(find.byType(FlutterMap))), isTrue);
    expect(
      identical(journeyMap, tester.state(find.byType(JourneyMap))),
      isTrue,
    );
    expect(camera(tester).center, center, reason: '0 refits: the pan is kept');
    expect(camera(tester).zoom, zoom);
    expect(tiles.requested.length, requested, reason: '0 new tile requests');
    expect(tiles.disposed, isFalse);
    expect(identical(plan(tester), before.plan), isTrue, reason: '0 new plans');
    expect(
      loads(),
      before.loads,
      reason: '0 refetches, 0 extra routes.min.json loads',
    );
    expect(find.byKey(const Key('selected-option-F10')), findsOneWidget);
    expect(find.byKey(const Key('map-card')), findsOneWidget);
    expect(
      rideColour(tester),
      paletteTheme(AppPalette.rose, Brightness.light).colorScheme.primary,
    );

    // Brightness, not the palette, switches the basemap.
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(template(tester), BasemapEndpoints.nightTiles);
    expect(identical(map, tester.state(find.byType(FlutterMap))), isTrue);
    expect(camera(tester).center, center);
    expect(loads(), before.loads);

    // A palette change in dark keeps Night and requests nothing new.
    requested = tiles.requested.length;
    await choose(
      tester,
      AppPalette.orange,
      eachFrame: (_) => expect(template(tester), BasemapEndpoints.nightTiles),
    );
    expect(tiles.requested.length, requested);
    expect(camera(tester).center, center);
    expect(identical(plan(tester), before.plan), isTrue);
    expect(loads(), before.loads);
    expect(find.byKey(const Key('selected-option-F10')), findsOneWidget);
    expect(
      rideColour(tester),
      paletteTheme(AppPalette.orange, Brightness.dark).colorScheme.primary,
    );
    expect(tester.takeException(), isNull);
  });
}
