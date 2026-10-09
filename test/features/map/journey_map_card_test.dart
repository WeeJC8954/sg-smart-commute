// P2-M1 widget tests: the optional journey map. Location, place search, bus
// data, tiles, the OneMap logo and the link launcher are all fakes
// (integration_test/fakes/), so no tile is fetched and no browser opened.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:sg_smart_commute/core/config/app_config.dart';
import 'package:sg_smart_commute/core/errors/app_failure.dart';
import 'package:sg_smart_commute/core/geo/geo.dart';
import 'package:sg_smart_commute/core/location/location_service.dart';
import 'package:sg_smart_commute/features/journey/data/mrt_asset_repository.dart';
import 'package:sg_smart_commute/features/journey/domain/mrt.dart';
import 'package:sg_smart_commute/features/map/domain/map_scene.dart';
import 'package:sg_smart_commute/features/map/domain/ride_geometry.dart';
import 'package:sg_smart_commute/features/map/domain/route_geometry.dart';
import 'package:sg_smart_commute/features/map/map_providers.dart';
import 'package:sg_smart_commute/features/map/presentation/basemap.dart';
import 'package:sg_smart_commute/features/map/presentation/journey_map.dart';

import '../../../integration_test/fakes/fake_bus_arrival_repository.dart';
import '../../../integration_test/fakes/fake_bus_network.dart';
import '../../../integration_test/fakes/fake_environment_repository.dart';
import '../../../integration_test/fakes/fake_location_service.dart';
import '../../../integration_test/fakes/fake_map.dart';
import '../../../integration_test/fakes/fake_place_search_repository.dart';
import '../../../integration_test/fakes/fake_route_geometry.dart';
import '../../../integration_test/fakes/test_app.dart';

const bishan = LatLng(1.3508, 103.8485);
const destinationField = Key('destination-field');
const showMap = Key('show-map');
const hideMap = Key('hide-map');

Future<void> pumpApp(WidgetTester tester, Widget app) async {
  tester.view.physicalSize = const Size(1080, 5000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
  await tester.pump();
}

Future<void> pickDestination(
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

Future<void> openMap(WidgetTester tester) async {
  await tester.tap(find.byKey(showMap));
  await tester.pump();
  await tester.pump();
}

Finder marker(String kind) => find.byKey(Key('map-marker-$kind'));

/// The nearest [Focus] above [finder]'s widget has the primary focus.
bool focusedAt(WidgetTester tester, Finder finder) =>
    Focus.maybeOf(
      tester.element(finder),
      createDependency: false,
    )?.hasPrimaryFocus ??
    false;

/// The drawn position of the marker of [kind].
LatLng pointOf(WidgetTester tester, String kind) {
  final m = tester
      .widget<MarkerLayer>(find.byType(MarkerLayer))
      .markers
      .firstWhere((m) => m.key == Key('map-marker-$kind'));
  return LatLng(m.point.latitude, m.point.longitude);
}

/// The drawn bus ride line.
List<LatLng> ridePoints(WidgetTester tester) => [
  for (final p
      in tester
          .widget<PolylineLayer>(find.byKey(const Key('map-ride-line')))
          .polylines
          .single
          .points)
    LatLng(p.latitude, p.longitude),
];

/// [points] are exactly the fake stops [codes], in order (the fake route
/// geometry runs straight through each direction's stops, so a ride's line is
/// its stops; 1e-5 is the polyline's precision).
void expectLineThrough(List<LatLng> points, List<String> codes) {
  final stops = fakeBusNetwork().stops;
  expect(points, hasLength(codes.length), reason: '$points');
  for (var i = 0; i < codes.length; i++) {
    final at = stops[codes[i]]!.position;
    expect(points[i].latitude, closeTo(at.latitude, 1e-5), reason: codes[i]);
    expect(points[i].longitude, closeTo(at.longitude, 1e-5), reason: codes[i]);
  }
}

/// Taps the journey card's "Select" for [service]'s option (P2-M3). Not
/// scrollToAndTap: widget tests import only the fakes from integration_test/.
Future<void> selectOption(WidgetTester tester, String service) async {
  final button = find.byKey(Key('select-option-$service'));
  await tester.ensureVisible(button);
  await tester.pump();
  await tester.tap(button);
  await tester.pump();
  await tester.pump();
}

/// Each stations() call waits on its own gate. The real repository caches a
/// success, which would make a later suggestion instant and hide the frames
/// in which the previous journey's value is still held while it reloads.
class HeldMrtRepository extends MrtAssetRepository {
  HeldMrtRepository() : super(load: () async => '');

  final gates = <Completer<List<MrtStation>>>[];

  @override
  Future<List<MrtStation>> stations() {
    final gate = Completer<List<MrtStation>>();
    gates.add(gate);
    return gate.future;
  }
}

void main() {
  late FakeBusNetworkRepository bus;
  late FakeRouteGeometryRepository geometry;
  late FakeTileProvider tiles;
  late FakeLinkOpener links;

  setUp(() {
    bus = FakeBusNetworkRepository();
    geometry = FakeRouteGeometryRepository();
    tiles = FakeTileProvider();
    links = FakeLinkOpener();
  });

  Widget app({
    FakeTileProvider? tileProvider,
    MrtAssetRepository? mrt,
    LatLng at = bishan,
  }) => buildTestApp(
    location: FakeLocationService(access: LocationAccess.granted, position: at),
    environment: FakeEnvironmentRepository(),
    places: FakePlaceSearchRepository(),
    busNetwork: bus,
    mrt: mrt ?? fakeMrtRepository(),
    busArrivals: FakeBusArrivalRepository(),
    routeGeometry: geometry,
    mapTiles: () => tileProvider ?? tiles,
    openLink: links.call,
  );

  testWidgets('no map control until a journey exists', (tester) async {
    await pumpApp(tester, app());
    expect(find.text('From: Current location'), findsOneWidget);
    expect(find.byKey(showMap), findsNothing);
    expect(find.byType(FlutterMap), findsNothing);
  });

  testWidgets('collapsed by default: no map and no tile request until '
      '"Show map"', (tester) async {
    await pumpApp(tester, app());
    await pickDestination(tester, 'VivoCity', 'VIVOCITY');
    await tester.pump(const Duration(seconds: 5));

    expect(find.byKey(showMap), findsOneWidget);
    expect(find.byType(FlutterMap), findsNothing);
    expect(find.byType(TileLayer), findsNothing);
    expect(tiles.requested, isEmpty);

    await openMap(tester);
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(tiles.requested, isNotEmpty);
    expect(find.byKey(const Key('basemap-attribution')), findsOneWidget);
  });

  testWidgets('markers for origin, boarding and alighting stops, and '
      'destination, from the suggested option', (tester) async {
    await pumpApp(tester, app());
    await pickDestination(tester, 'VivoCity', 'VIVOCITY');
    await openMap(tester);

    for (final kind in ['origin', 'boarding', 'alighting', 'destination']) {
      expect(marker(kind), findsOneWidget, reason: kind);
    }
    // F20 from BSH2 to VIV1 is the suggested option (fake_bus_network.dart).
    final stops = fakeBusNetwork().stops;
    final layer = tester.widget<MarkerLayer>(find.byType(MarkerLayer));
    final points = {
      for (final m in layer.markers)
        (m.key! as ValueKey<String>).value: (
          m.point.latitude,
          m.point.longitude,
        ),
    };
    expect(points['map-marker-boarding'], (
      stops['BSH2']!.position.latitude,
      stops['BSH2']!.position.longitude,
    ));
    expect(points['map-marker-alighting'], (
      stops['VIV1']!.position.latitude,
      stops['VIV1']!.position.longitude,
    ));
    expect(bus.loads, 1, reason: 'the map reads the plan, it never plans');
  });

  testWidgets('while the bus is being found, only the two ends are marked', (
    tester,
  ) async {
    bus.hold();
    await pumpApp(tester, app());
    await pickDestination(tester, 'VivoCity', 'VIVOCITY');
    await openMap(tester);

    expect(marker('origin'), findsOneWidget);
    expect(marker('destination'), findsOneWidget);
    expect(marker('boarding'), findsNothing);
    expect(marker('alighting'), findsNothing);

    bus.release();
    await tester.pump();
    await tester.pump();
    expect(marker('boarding'), findsOneWidget);
    expect(marker('alighting'), findsOneWidget);
  });

  testWidgets('the camera fits the journey inside OneMap\'s bounds and zoom '
      'range', (tester) async {
    await pumpApp(tester, app());
    await pickDestination(tester, 'VivoCity', 'VIVOCITY');
    await openMap(tester);

    final camera = MapCamera.of(tester.element(find.byType(MarkerLayer)));
    expect(
      camera.zoom,
      inInclusiveRange(MapConfig.minZoom, MapConfig.fitMaxZoom),
    );
    expect(camera.minZoom, MapConfig.minZoom);
    expect(camera.maxZoom, MapConfig.maxZoom);
    final visible = camera.visibleBounds;
    for (final m
        in tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers) {
      expect(visible.contains(m.point), isTrue, reason: '${m.key}');
    }
    expect(visible.south, greaterThanOrEqualTo(MapConfig.boundsSouth));
    expect(visible.north, lessThanOrEqualTo(MapConfig.boundsNorth));
    expect(visible.west, greaterThanOrEqualTo(MapConfig.boundsWest));
    expect(visible.east, lessThanOrEqualTo(MapConfig.boundsEast));
  });

  testWidgets(
    'the first tiles requested are those of the fitted view, none at a '
    'default camera first',
    (tester) async {
      await pumpApp(tester, app());
      await pickDestination(tester, 'VivoCity', 'VIVOCITY');
      await openMap(tester);
      await tester.pump();

      final camera = MapCamera.of(tester.element(find.byType(MarkerLayer)));
      expect(tiles.requested, isNotEmpty);
      expect(tiles.requested.map((t) => t.z).toSet(), {
        camera.zoom.round(),
      }, reason: 'a tile at another zoom would be a wasted OneMap request');
    },
  );

  testWidgets('OneMap Default tiles in light mode, Night tiles in dark mode', (
    tester,
  ) async {
    await pumpApp(tester, app());
    await pickDestination(tester, 'VivoCity', 'VIVOCITY');
    await openMap(tester);
    expect(
      tester.widget<TileLayer>(find.byType(TileLayer)).urlTemplate,
      BasemapEndpoints.defaultTiles,
    );

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    // MaterialApp animates the theme change.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tester.widget<TileLayer>(find.byType(TileLayer)).urlTemplate,
      BasemapEndpoints.nightTiles,
    );
    expect(tiles.disposed, isFalse, reason: 'the same provider is reused');
  });

  testWidgets('the attribution is always visible, with the logo and both '
      'names linked', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpApp(tester, app());
    await pickDestination(tester, 'VivoCity', 'VIVOCITY');
    await openMap(tester);

    final attribution = find.byKey(const Key('basemap-attribution'));
    expect(
      find.descendant(of: attribution, matching: find.byType(Image)),
      findsOneWidget,
    );
    final logo = tester.widget<Image>(
      find.descendant(of: attribution, matching: find.byType(Image)),
    );
    expect((logo.width, logo.height), (20.0, 20.0));
    expect(logo.semanticLabel, 'OneMap logo');
    final texts = tester
        .widgetList<Text>(
          find.descendant(of: attribution, matching: find.byType(Text)),
        )
        .map((t) => t.data)
        .join();
    expect(texts, 'OneMap © contributors | Singapore Land Authority');

    // Outside the map: nothing on the map can cover it.
    expect(
      find.descendant(of: find.byType(FlutterMap), matching: attribution),
      findsNothing,
    );

    for (final (key, url) in [
      ('attribution-onemap', 'https://www.onemap.gov.sg/'),
      ('attribution-sla', 'https://www.sla.gov.sg/'),
    ]) {
      final node = tester.getSemantics(find.byKey(Key(key)));
      expect(node.flagsCollection.isLink, isTrue, reason: key);
      expect(node.linkUrl, Uri.parse(url), reason: key);
    }

    await tester.tap(find.byKey(const Key('attribution-onemap')));
    await tester.tap(find.byKey(const Key('attribution-sla')));
    await tester.pump();
    expect(links.opened, [
      Uri.parse('https://www.onemap.gov.sg/'),
      Uri.parse('https://www.sla.gov.sg/'),
    ]);
    handle.dispose();
  });

  testWidgets('a link that cannot be opened only shows a note', (tester) async {
    links.result = false;
    await pumpApp(tester, app());
    await pickDestination(tester, 'VivoCity', 'VIVOCITY');
    await openMap(tester);

    await tester.tap(find.byKey(const Key('attribution-sla')));
    await tester.pump();
    expect(find.text("Couldn't open www.sla.gov.sg."), findsOneWidget);
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.byKey(const Key('journey-card')), findsOneWidget);
  });

  testWidgets('tiles that fail: a degraded note, no retry, and the journey '
      'card is unaffected', (tester) async {
    final failing = FakeTileProvider(fail: true);
    await pumpApp(tester, app(tileProvider: failing));
    await pickDestination(tester, 'VivoCity', 'VIVOCITY');
    await openMap(tester);
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('map-tiles-unavailable')), findsOneWidget);
    expect(find.text(JourneyMap.tilesUnavailable), findsOneWidget);
    // Announced as itself, not as the whole map card it sits in (#67).
    final handle = tester.ensureSemantics();
    await tester.pump();
    expect(
      tester.getSemantics(find.text(JourneyMap.tilesUnavailable)),
      isSemantics(label: JourneyMap.tilesUnavailable, isLiveRegion: true),
    );
    handle.dispose();
    // Below the map, never over a marker.
    expect(
      tester.getTopLeft(find.byKey(const Key('map-tiles-unavailable'))).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(find.byType(FlutterMap)).dy),
    );
    // Markers and the attribution still show.
    expect(marker('boarding'), findsOneWidget);
    expect(find.byKey(const Key('basemap-attribution')), findsOneWidget);

    final asked = failing.requested.length;
    await tester.pump(const Duration(minutes: 2));
    expect(failing.requested.length, asked, reason: 'no automatic retry');

    // The journey answer is all still there and usable.
    expect(find.text('Suggested'), findsOneWidget);
    expect(find.text('Take Bus F20 toward VivoCity (fake)'), findsOneWidget);
  });

  testWidgets('"Hide map" removes the map; it stays open across journeys and '
      'follows the current one', (tester) async {
    await pumpApp(tester, app());
    await pickDestination(tester, 'VivoCity', 'VIVOCITY');
    await openMap(tester);
    expect(marker('boarding'), findsOneWidget);

    // A new destination while open: still open, showing the new journey.
    await tester.tap(find.byKey(const Key('change-destination')));
    await tester.pump();
    await pickDestination(tester, 'ION Orchard', 'ION ORCHARD');
    expect(find.byType(FlutterMap), findsOneWidget);
    final layer = tester.widget<MarkerLayer>(find.byType(MarkerLayer));
    final alight = layer.markers.firstWhere(
      (m) => m.key == const Key('map-marker-alighting'),
    );
    expect(
      alight.point.latitude,
      fakeBusNetwork().stops['ION1']!.position.latitude,
    );

    await tester.tap(find.byKey(hideMap));
    await tester.pump();
    expect(find.byType(FlutterMap), findsNothing);
    expect(find.byKey(showMap), findsOneWidget);
    expect(tiles.disposed, isTrue, reason: 'closing the map ends its tiles');
  });

  testWidgets('"Show map" moves focus to "Hide map", and back (#56)', (
    tester,
  ) async {
    await pumpApp(tester, app());
    await pickDestination(tester, 'VivoCity', 'VIVOCITY');
    await openMap(tester);
    expect(focusedAt(tester, find.text('Hide map')), isTrue);
    await tester.tap(find.byKey(hideMap));
    await tester.pump();
    await tester.pump();
    expect(focusedAt(tester, find.text('Show map')), isTrue);
  });

  testWidgets('the map never takes focus by itself; focused, it has a ring '
      'and reads as its summary (#58)', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpApp(tester, app());
    await pickDestination(tester, 'VivoCity', 'VIVOCITY');
    await openMap(tester);
    final keyboard = tester
        .widget<FlutterMap>(find.byType(FlutterMap))
        .options
        .interactionOptions
        .keyboardOptions;
    expect(keyboard.autofocus, isFalse);
    expect(keyboard.focusNode, isNotNull);
    expect(keyboard.focusNode!.hasFocus, isFalse);
    // Keyboard panning stays (docs/assumptions.md, map gestures).
    expect(keyboard.enableArrowKeysPanning, isTrue);

    final summary = find.bySemanticsLabel(
      RegExp(r'^Map of the suggested journey'),
    );
    final ring = find.ancestor(
      of: find.byType(FlutterMap),
      matching: find.byWidgetPredicate(
        (w) =>
            w is DecoratedBox &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).border != null,
      ),
    );
    expect(ring, findsNothing);
    expect(tester.getSemantics(summary), isNot(isSemantics(isFocused: true)));

    // As a keyboard user reaches it.
    await tester.sendKeyEvent(LogicalKeyboardKey.shift);
    keyboard.focusNode!.requestFocus();
    await tester.pump();
    expect(ring, findsOneWidget);
    expect(tester.getSemantics(summary), isSemantics(isFocused: true));
    handle.dispose();
  });

  testWidgets('the map is one summary for screen readers', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpApp(tester, app());
    await pickDestination(tester, 'VivoCity', 'VIVOCITY');
    await openMap(tester);
    expect(
      find.bySemanticsLabel(
        RegExp(
          r'^Map of the suggested journey: from Current location, bus F20',
        ),
      ),
      findsOneWidget,
    );
    handle.dispose();
  });

  group('route geometry (P2-M2)', () {
    testWidgets('no routes.min.json request before "Show map"', (tester) async {
      await pumpApp(tester, app());
      await pickDestination(tester, 'VivoCity', 'VIVOCITY');
      await tester.pump(const Duration(seconds: 5));
      expect(geometry.loads, 0);
      await openMap(tester);
      expect(geometry.loads, 1);
    });

    testWidgets('a walk-only journey never requests it, even with the map '
        'open', (tester) async {
      await pumpApp(tester, app());
      // Bishan MRT (NS17) is about 30 m from the fake fix: walk-only.
      await pickDestination(tester, 'Bishan MRT', 'BISHAN MRT STATION (NS17)');
      expect(find.byKey(const Key('journey-walk-only')), findsOneWidget);
      await openMap(tester);
      await tester.pump(const Duration(seconds: 5));
      expect(find.byType(FlutterMap), findsOneWidget);
      expect(geometry.loads, 0);
      expect(bus.loads, 0, reason: 'walk-only never touches bus data');
    });

    testWidgets('one load per session: hide, reopen, change journey', (
      tester,
    ) async {
      await pumpApp(tester, app());
      await pickDestination(tester, 'VivoCity', 'VIVOCITY');
      await openMap(tester);
      await tester.tap(find.byKey(hideMap));
      await tester.pump();
      await openMap(tester);
      await tester.tap(find.byKey(const Key('change-destination')));
      await tester.pump();
      await pickDestination(tester, 'ION Orchard', 'ION ORCHARD');
      expect(geometry.loads, 1);
    });

    testWidgets('a failed load is not retried until the user opens the map '
        'again', (tester) async {
      geometry.failure = const StaticDataUnavailable(
        StaticDataset.busRouteGeometry,
      );
      await pumpApp(tester, app());
      await pickDestination(tester, 'VivoCity', 'VIVOCITY');
      await openMap(tester);
      await tester.pump(const Duration(minutes: 2));
      expect(geometry.loads, 1, reason: 'no automatic retry');
      expect(marker('boarding'), findsOneWidget);

      geometry.failure = null;
      await tester.tap(find.byKey(hideMap));
      await tester.pump();
      await openMap(tester);
      expect(geometry.loads, 2);
    });

    testWidgets('reopening after a successful load does not load again', (
      tester,
    ) async {
      await pumpApp(tester, app());
      await pickDestination(tester, 'VivoCity', 'VIVOCITY');
      await openMap(tester);
      await tester.tap(find.byKey(hideMap));
      await tester.pump();
      await openMap(tester);
      expect(geometry.loads, 1);
    });

    testWidgets('the line is drawn once the geometry has loaded', (
      tester,
    ) async {
      await pumpApp(tester, app());
      await pickDestination(tester, 'VivoCity', 'VIVOCITY');
      await openMap(tester);
      expect(find.byKey(const Key('map-ride-line')), findsOneWidget);
    });

    testWidgets('a failed load shows the unavailable note, then the line '
        'after the user retries', (tester) async {
      geometry.failure = const StaticDataUnavailable(
        StaticDataset.busRouteGeometry,
      );
      await pumpApp(tester, app());
      await pickDestination(tester, 'VivoCity', 'VIVOCITY');
      await openMap(tester);
      expect(find.byKey(const Key('map-ride-unavailable')), findsOneWidget);
      expect(find.text(JourneyMap.rideLineUnavailable), findsOneWidget);
      geometry.failure = null;
      await tester.tap(find.byKey(hideMap));
      await tester.pump();
      await openMap(tester);
      expect(find.byKey(const Key('map-ride-line')), findsOneWidget);
      expect(find.byKey(const Key('map-ride-unavailable')), findsNothing);
    });

    testWidgets('the suggested ride is drawn on the road, under the markers', (
      tester,
    ) async {
      await pumpApp(tester, app());
      await pickDestination(tester, 'VivoCity', 'VIVOCITY');
      await openMap(tester);
      await tester.pump();
      final layer = tester.widget<PolylineLayer>(
        find.byKey(const Key('map-ride-line')),
      );
      final points = layer.polylines.single.points;
      final stops = fakeBusNetwork().stops; // F20: BSH2 -> MID1 -> VIV1
      expect(
        points.first.latitude,
        closeTo(stops['BSH2']!.position.latitude, 1e-4),
      );
      expect(
        points.last.latitude,
        closeTo(stops['VIV1']!.position.latitude, 1e-4),
      );
      // Drawn before the markers, so the pins stay on top.
      final children = tester
          .widget<FlutterMap>(find.byType(FlutterMap))
          .children;
      expect(
        children.indexWhere((w) => w.key == const Key('map-ride-line')),
        lessThan(children.indexWhere((w) => w is MarkerLayer)),
      );
    });

    testWidgets('geometry that cannot be matched: markers, a note, no line, '
        'journey card unchanged', (tester) async {
      geometry.geometry = RouteGeometry({
        'F20': [
          encodePolyline(const [LatLng(1.40, 103.70), LatLng(1.41, 103.71)]),
        ],
      }); // nowhere near the ride
      await pumpApp(tester, app());
      await pickDestination(tester, 'VivoCity', 'VIVOCITY');
      await openMap(tester);
      await tester.pump();
      expect(find.byKey(const Key('map-ride-line')), findsNothing);
      expect(find.byKey(const Key('map-ride-unavailable')), findsOneWidget);
      for (final k in ['origin', 'boarding', 'alighting', 'destination']) {
        expect(marker(k), findsOneWidget, reason: k);
      }
      expect(find.text('Take Bus F20 toward VivoCity (fake)'), findsOneWidget);
    });

    testWidgets('a malformed line fails only its own ride: markers and a '
        'note, journey unchanged; another service is still drawn', (
      tester,
    ) async {
      final network = fakeBusNetwork();
      geometry.geometry = RouteGeometry({
        for (final s in network.services.values)
          s.number: [
            for (final codes in s.directions)
              encodePolyline([
                for (final c in codes) network.stops[c]!.position,
              ]),
          ],
        'F20': ['_p~iF'], // a latitude without its longitude
      });
      await pumpApp(tester, app());
      await pickDestination(tester, 'VivoCity', 'VIVOCITY');
      await openMap(tester);
      await tester.pump();
      expect(find.byKey(const Key('map-ride-line')), findsNothing);
      expect(find.byKey(const Key('map-ride-unavailable')), findsOneWidget);
      for (final k in ['origin', 'boarding', 'alighting', 'destination']) {
        expect(marker(k), findsOneWidget, reason: k);
      }
      expect(find.text('Take Bus F20 toward VivoCity (fake)'), findsOneWidget);

      await tester.tap(find.byKey(const Key('change-destination')));
      await tester.pump();
      await pickDestination(tester, 'ION Orchard', 'ION ORCHARD'); // F30
      await tester.pump();
      expect(find.byKey(const Key('map-ride-line')), findsOneWidget);
      expect(find.byKey(const Key('map-ride-unavailable')), findsNothing);
      expect(geometry.loads, 1, reason: 'the same loaded file serves both');
    });

    testWidgets('no note while the line loads, and none for a walk-only '
        'journey', (tester) async {
      geometry.hold();
      await pumpApp(tester, app());
      await pickDestination(tester, 'VivoCity', 'VIVOCITY');
      await openMap(tester);
      expect(find.byKey(const Key('map-ride-unavailable')), findsNothing);
      expect(find.byKey(const Key('map-ride-line')), findsNothing);
      geometry.release();
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('map-ride-line')), findsOneWidget);

      await tester.tap(find.byKey(const Key('change-destination')));
      await tester.pump();
      await pickDestination(tester, 'Bishan MRT', 'BISHAN MRT STATION (NS17)');
      expect(find.byKey(const Key('journey-walk-only')), findsOneWidget);
      expect(find.byKey(const Key('map-ride-line')), findsNothing);
      expect(find.byKey(const Key('map-ride-unavailable')), findsNothing);
    });

    testWidgets('changing journey while the line loads never shows the old '
        'line', (tester) async {
      geometry.hold();
      await pumpApp(tester, app());
      await pickDestination(tester, 'VivoCity', 'VIVOCITY');
      await openMap(tester);
      await tester.tap(find.byKey(const Key('change-destination')));
      await tester.pump();
      await pickDestination(tester, 'ION Orchard', 'ION ORCHARD'); // F30
      geometry.release();
      await tester.pump();
      await tester.pump();
      final points = tester
          .widget<PolylineLayer>(find.byKey(const Key('map-ride-line')))
          .polylines
          .single
          .points;
      final ion = fakeBusNetwork().stops['ION1']!.position;
      expect(points.last.latitude, closeTo(ion.latitude, 1e-4));
    });

    testWidgets(
      'a failure held from a bus journey is not retried by "Show map" '
      'on a walk-only journey',
      (tester) async {
        geometry.failure = const StaticDataUnavailable(
          StaticDataset.busRouteGeometry,
        );
        await pumpApp(tester, app());
        await pickDestination(tester, 'VivoCity', 'VIVOCITY');
        await openMap(tester);
        expect(geometry.loads, 1);
        await tester.tap(find.byKey(hideMap));
        await tester.pump();

        await tester.tap(find.byKey(const Key('change-destination')));
        await tester.pump();
        await pickDestination(
          tester,
          'Bishan MRT',
          'BISHAN MRT STATION (NS17)',
        );
        expect(find.byKey(const Key('journey-walk-only')), findsOneWidget);
        await openMap(tester);
        await tester.pump(const Duration(seconds: 5));
        expect(find.byType(FlutterMap), findsOneWidget);
        expect(geometry.loads, 1, reason: 'nothing is requested for walk-only');
      },
    );

    testWidgets('a held failure is not flushed by repeated "Show map" on a '
        'walk-only journey; a later bus journey retries on "Show map"', (
      tester,
    ) async {
      geometry.failure = const StaticDataUnavailable(
        StaticDataset.busRouteGeometry,
      );
      await pumpApp(tester, app());
      await pickDestination(tester, 'VivoCity', 'VIVOCITY');
      await openMap(tester);
      expect(geometry.loads, 1);
      await tester.tap(find.byKey(hideMap));
      await tester.pump();
      await tester.tap(find.byKey(const Key('change-destination')));
      await tester.pump();
      await pickDestination(tester, 'Bishan MRT', 'BISHAN MRT STATION (NS17)');
      expect(find.byKey(const Key('journey-walk-only')), findsOneWidget);

      for (var i = 0; i < 2; i++) {
        await openMap(tester);
        await tester.pump(const Duration(seconds: 5));
        await tester.tap(find.byKey(hideMap));
        await tester.pump();
      }
      expect(geometry.loads, 1, reason: 'walk-only: nothing is requested');

      // Back to a bus journey: the user's next "Show map" is the retry.
      geometry.failure = null;
      await tester.tap(find.byKey(const Key('change-destination')));
      await tester.pump();
      await pickDestination(tester, 'VivoCity', 'VIVOCITY');
      expect(geometry.loads, 1, reason: 'a closed map requests nothing');
      await openMap(tester);
      expect(geometry.loads, 2);
      expect(find.byKey(const Key('map-ride-line')), findsOneWidget);
    });

    testWidgets('"Show map" during a retry that is still loading does not '
        'start another', (tester) async {
      geometry.failure = const StaticDataUnavailable(
        StaticDataset.busRouteGeometry,
      );
      await pumpApp(tester, app());
      await pickDestination(tester, 'VivoCity', 'VIVOCITY');
      await openMap(tester);
      expect(geometry.loads, 1);

      geometry.failure = null;
      geometry.hold();
      await tester.tap(find.byKey(hideMap));
      await tester.pump();
      await openMap(tester);
      expect(geometry.loads, 2);
      // No note while the retry is pending, although the last result failed.
      expect(find.byKey(const Key('map-ride-unavailable')), findsNothing);

      await tester.tap(find.byKey(hideMap));
      await tester.pump();
      await openMap(tester);
      expect(geometry.loads, 2, reason: 'the retry is already under way');

      geometry.release();
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('map-ride-line')), findsOneWidget);
      expect(geometry.loads, 2);
    });

    testWidgets('a retry in progress shows no unavailable note: absent '
        'while it loads', (tester) async {
      geometry.failure = const StaticDataUnavailable(
        StaticDataset.busRouteGeometry,
      );
      await pumpApp(tester, app());
      await pickDestination(tester, 'VivoCity', 'VIVOCITY');
      await openMap(tester);
      expect(find.byKey(const Key('map-ride-unavailable')), findsOneWidget);

      geometry.hold(); // the retry fails again, but only after the gate opens
      await tester.tap(find.byKey(hideMap));
      await tester.pump();
      await openMap(tester);
      expect(geometry.loads, 2);
      expect(find.byKey(const Key('map-ride-unavailable')), findsNothing);

      geometry.release();
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('map-ride-unavailable')), findsOneWidget);
    });

    testWidgets('a line worked out for another ride is never drawn', (
      tester,
    ) async {
      const a = LatLng(1.35, 103.85), b = LatLng(1.36, 103.86);
      const rideA = MapRide(service: 'F20', sourceDirection: 0, stops: [a, b]);
      const rideB = MapRide(service: 'F30', sourceDirection: 0, stops: [a, b]);
      const scene = MapScene(
        [
          MapMarker(MapMarkerKind.origin, a, 'Start'),
          MapMarker(MapMarkerKind.boarding, a, 'Stop A'),
          MapMarker(MapMarkerKind.alighting, b, 'Stop B'),
          MapMarker(MapMarkerKind.destination, b, 'End'),
        ],
        serviceNumber: 'F20',
        ride: rideA,
      );
      tester.view.physicalSize = const Size(1080, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mapTileProviderFactoryProvider.overrideWithValue(() => tiles),
            rideLineProvider.overrideWithValue(
              const AsyncData(RideLineDrawn(rideB, [a, b])),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: JourneyMap(scene: scene)),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.byKey(const Key('map-ride-line')), findsNothing);
      expect(find.byKey(const Key('map-ride-unavailable')), findsNothing);

      // The same holds for a gap worked out for another ride: no note.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mapTileProviderFactoryProvider.overrideWithValue(() => tiles),
            rideLineProvider.overrideWithValue(
              const AsyncData(
                RideLineUnavailable(rideB, RideLineGap.notMatched),
              ),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: JourneyMap(scene: scene)),
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('map-ride-unavailable')), findsNothing);

      // ...while a gap for this very ride does show the note.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mapTileProviderFactoryProvider.overrideWithValue(() => tiles),
            rideLineProvider.overrideWithValue(
              const AsyncData(
                RideLineUnavailable(rideA, RideLineGap.notMatched),
              ),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: JourneyMap(scene: scene)),
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('map-ride-unavailable')), findsOneWidget);
    });
  });

  group('option sync and MRT (P2-M3)', () {
    final stops = fakeBusNetwork().stops;

    testWidgets('the suggested option is drawn first: F20 along its own '
        'stops', (tester) async {
      await pumpApp(tester, app());
      await pickDestination(tester, 'VivoCity', 'VIVOCITY');
      await openMap(tester);
      await tester.pump();
      expect(pointOf(tester, 'boarding'), stops['BSH2']!.position);
      expectLineThrough(ridePoints(tester), ['BSH2', 'MID1', 'VIV1']);
    });

    testWidgets('selecting F10 moves the boarding marker and draws F10\'s '
        'line exactly; one load', (tester) async {
      await pumpApp(tester, app());
      await pickDestination(tester, 'VivoCity', 'VIVOCITY');
      await openMap(tester);
      await tester.pump();
      await selectOption(tester, 'F10');
      expect(pointOf(tester, 'boarding'), stops['BSH1']!.position);
      expect(pointOf(tester, 'alighting'), stops['VIV1']!.position);
      // F10 is BSH1 → MID1 → MID2 → VIV1; F20 (BSH2 → MID1 → VIV1) also
      // passes MID1, so only the whole line tells them apart.
      expectLineThrough(ridePoints(tester), ['BSH1', 'MID1', 'MID2', 'VIV1']);
      expect(geometry.loads, 1);
    });

    testWidgets('F10 → F30: the same stops, a different line (via ION1)', (
      tester,
    ) async {
      await pumpApp(tester, app());
      await pickDestination(tester, 'VivoCity', 'VIVOCITY');
      await openMap(tester);
      await tester.pump();
      await selectOption(tester, 'F10');
      await selectOption(tester, 'F30');
      expect(pointOf(tester, 'boarding'), stops['BSH1']!.position);
      expectLineThrough(ridePoints(tester), ['BSH1', 'ION1', 'MID2', 'VIV1']);
      expect(geometry.loads, 1);
    });

    testWidgets('a new plan resets the map to its suggestion: F10, then ION '
        'Orchard, then VivoCity again shows F20 from BSH2', (tester) async {
      await pumpApp(tester, app());
      await pickDestination(tester, 'VivoCity', 'VIVOCITY');
      await openMap(tester);
      await tester.pump();
      await selectOption(tester, 'F10');
      expect(pointOf(tester, 'boarding'), stops['BSH1']!.position);
      expectLineThrough(ridePoints(tester), ['BSH1', 'MID1', 'MID2', 'VIV1']);

      await tester.tap(find.byKey(const Key('change-destination')));
      await tester.pump();
      await pickDestination(tester, 'ION Orchard', 'ION ORCHARD');
      await tester.tap(find.byKey(const Key('change-destination')));
      await tester.pump();
      await pickDestination(tester, 'VivoCity', 'VIVOCITY'); // a new plan
      await tester.pump();

      expect(pointOf(tester, 'boarding'), stops['BSH2']!.position);
      expectLineThrough(ridePoints(tester), ['BSH2', 'MID1', 'VIV1']);
      expect(geometry.loads, 1);
    });

    testWidgets('select while the map is closed: no tile, no geometry; '
        'opening shows the selection', (tester) async {
      await pumpApp(tester, app());
      await pickDestination(tester, 'VivoCity', 'VIVOCITY');
      await selectOption(tester, 'F10');
      expect(geometry.loads, 0);
      expect(tiles.requested, isEmpty);
      await openMap(tester);
      await tester.pump();
      expect(pointOf(tester, 'boarding'), stops['BSH1']!.position);
      expectLineThrough(ridePoints(tester), ['BSH1', 'MID1', 'MID2', 'VIV1']);
      expect(geometry.loads, 1);
    });

    testWidgets('the selection survives Hide map / Show map; no second '
        'load', (tester) async {
      await pumpApp(tester, app());
      await pickDestination(tester, 'VivoCity', 'VIVOCITY');
      await openMap(tester);
      await tester.pump();
      await selectOption(tester, 'F10');
      await tester.tap(find.byKey(hideMap));
      await tester.pump();
      await openMap(tester);
      await tester.pump();
      expect(pointOf(tester, 'boarding'), stops['BSH1']!.position);
      expect(geometry.loads, 1);
    });

    testWidgets('the camera fits the selected option and the MRT markers', (
      tester,
    ) async {
      await pumpApp(tester, app());
      await pickDestination(tester, 'VivoCity', 'VIVOCITY');
      await openMap(tester);
      await tester.pump();
      await selectOption(tester, 'F10');
      final visible = MapCamera.of(tester.element(find.byType(MarkerLayer)))
          .visibleBounds;
      final markers = tester.widget<MarkerLayer>(find.byType(MarkerLayer));
      expect(marker('mrtNearOrigin'), findsOneWidget);
      for (final m in markers.markers) {
        expect(visible.contains(m.point), isTrue, reason: '${m.key}');
      }
      for (final code in ['BSH1', 'MID1', 'MID2', 'VIV1']) {
        final p = stops[code]!.position;
        expect(
          visible.contains(_toMap(p)),
          isTrue,
          reason: '$code (a ride stop)',
        );
      }
    });

    testWidgets("both MRT markers, with the card's wording as tooltips", (
      tester,
    ) async {
      await pumpApp(tester, app());
      await pickDestination(tester, 'VivoCity', 'VIVOCITY');
      await openMap(tester);
      await tester.pump();
      expect(marker('mrtNearOrigin'), findsOneWidget);
      expect(marker('mrtNearDestination'), findsOneWidget);
      expect(find.byTooltip('Nearest MRT: BISHAN MRT STATION'), findsOneWidget);
      expect(
        find.byTooltip('Near your destination: HARBOURFRONT MRT STATION'),
        findsOneWidget,
      );
    });

    testWidgets('while the MRT suggestion reloads for a new journey, no MRT '
        'marker (never the old one)', (tester) async {
      final mrt = HeldMrtRepository();
      await pumpApp(tester, app(mrt: mrt));
      await pickDestination(tester, 'VivoCity', 'VIVOCITY');
      await openMap(tester);
      await tester.pump();
      expect(marker('mrtNearOrigin'), findsNothing, reason: 'loading');
      mrt.gates.last.complete(fakeMrtStations);
      await tester.pump();
      await tester.pump();
      expect(
        find.byTooltip('Near your destination: HARBOURFRONT MRT STATION'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('change-destination')));
      await tester.pump();
      await pickDestination(tester, 'ION Orchard', 'ION ORCHARD');
      expect(mrt.gates, hasLength(2), reason: 'the suggestion re-runs');
      expect(
        find.byTooltip('Near your destination: HARBOURFRONT MRT STATION'),
        findsNothing,
      );
      expect(marker('mrtNearOrigin'), findsNothing);
      mrt.gates.last.complete(fakeMrtStations);
      await tester.pump();
      await tester.pump();
      expect(
        find.byTooltip('Near your destination: ORCHARD MRT STATION'),
        findsOneWidget,
      );
    });

    testWidgets('MRT failure: no MRT marker and no map note; the rest is '
        'unaffected', (tester) async {
      await pumpApp(tester, app(mrt: fakeMrtRepository(fail: true)));
      await pickDestination(tester, 'VivoCity', 'VIVOCITY');
      await openMap(tester);
      await tester.pump();
      expect(marker('mrtNearOrigin'), findsNothing);
      expect(marker('mrtNearDestination'), findsNothing);
      expect(marker('boarding'), findsOneWidget);
      expect(find.byKey(const Key('map-ride-line')), findsOneWidget);
    });
  });
  group('connectors, MRT pins and legend (P2-M3)', () {
    final stops = fakeBusNetwork().stops;
    const connectors = Key('map-walk-connectors');
    const legend = Key('map-legend');
    Finder inLegend(String text) =>
        find.descendant(of: find.byKey(legend), matching: find.text(text));

    testWidgets('two dashed connectors whose ends are exactly the markers; '
        'the bus line stays solid', (tester) async {
      await pumpApp(tester, app());
      await pickDestination(tester, 'VivoCity', 'VIVOCITY');
      await openMap(tester);
      await tester.pump();
      final walks = tester.widget<PolylineLayer>(find.byKey(connectors));
      expect(walks.polylines, hasLength(2));
      final at = {
        for (final m
            in tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers)
          m.key: m.point,
      };
      expect(walks.polylines[0].points, [
        at[const Key('map-marker-origin')],
        at[const Key('map-marker-boarding')],
      ]);
      expect(walks.polylines[1].points, [
        at[const Key('map-marker-alighting')],
        at[const Key('map-marker-destination')],
      ]);
      final ride = tester
          .widget<PolylineLayer>(find.byKey(const Key('map-ride-line')))
          .polylines
          .single;
      for (final w in walks.polylines) {
        // flutter_map 8.3.2's StrokePattern has value equality (the
        // segments compared by value). dashed() can't be const: its asserts
        // read the list's length.
        expect(w.pattern, StrokePattern.dashed(segments: const [10, 8]));
        expect(w.pattern.segments, [10, 8]);
        expect(w.strokeWidth, 3);
        expect(w.color, isNot(ride.color), reason: 'pin colour, not the bus');
      }
      expect(ride.pattern, const StrokePattern.solid());
      expect(ride.strokeWidth, 5);
    });

    testWidgets('layer order: connectors, ride line, markers; in the '
        'markers: MRT, ends, stops', (tester) async {
      await pumpApp(tester, app());
      await pickDestination(tester, 'VivoCity', 'VIVOCITY');
      await openMap(tester);
      await tester.pump();
      final children = tester
          .widget<FlutterMap>(find.byType(FlutterMap))
          .children;
      final walksAt = children.indexWhere((w) => w.key == connectors);
      final rideAt = children.indexWhere(
        (w) => w.key == const Key('map-ride-line'),
      );
      final markersAt = children.indexWhere((w) => w is MarkerLayer);
      expect(walksAt, isNonNegative);
      expect(walksAt, lessThan(rideAt));
      expect(rideAt, lessThan(markersAt));
      final keys = [
        for (final m
            in tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers)
          (m.key! as ValueKey<String>).value,
      ];
      expect(keys, [
        'map-marker-mrtNearOrigin',
        'map-marker-mrtNearDestination',
        'map-marker-origin',
        'map-marker-destination',
        'map-marker-boarding',
        'map-marker-alighting',
      ]);
    });

    testWidgets('connectors follow the selection (F10: origin → BSH1)', (
      tester,
    ) async {
      await pumpApp(tester, app());
      await pickDestination(tester, 'VivoCity', 'VIVOCITY');
      await openMap(tester);
      await tester.pump();
      await selectOption(tester, 'F10');
      final first = tester
          .widget<PolylineLayer>(find.byKey(connectors))
          .polylines
          .first
          .points;
      expect(first.first, _toMap(bishan));
      expect(first.last, _toMap(stops['BSH1']!.position));
    });

    testWidgets('connectors, markers and MRT stay when the ride line is '
        'unavailable', (tester) async {
      geometry.failure = const StaticDataUnavailable(
        StaticDataset.busRouteGeometry,
      );
      await pumpApp(tester, app());
      await pickDestination(tester, 'VivoCity', 'VIVOCITY');
      await openMap(tester);
      await tester.pump();
      expect(find.byKey(const Key('map-ride-line')), findsNothing);
      expect(find.byKey(const Key('map-ride-unavailable')), findsOneWidget);
      expect(
        tester.widget<PolylineLayer>(find.byKey(connectors)).polylines,
        hasLength(2),
      );
      expect(marker('mrtNearOrigin'), findsOneWidget);
      expect(marker('mrtNearDestination'), findsOneWidget);
      expect(inLegend(JourneyMap.walkLegend), findsOneWidget);
      expect(inLegend(JourneyMap.busLegend('F20')), findsNothing);
    });

    testWidgets('selecting while the line loads: the new ride only, never '
        'the old', (tester) async {
      geometry.hold();
      await pumpApp(tester, app());
      await pickDestination(tester, 'VivoCity', 'VIVOCITY');
      await openMap(tester);
      expect(find.byKey(const Key('map-ride-line')), findsNothing);
      expect(find.byKey(connectors), findsOneWidget, reason: 'needs no data');
      await selectOption(tester, 'F10');
      geometry.release();
      await tester.pump();
      await tester.pump();
      expectLineThrough(ridePoints(tester), ['BSH1', 'MID1', 'MID2', 'VIV1']);
      expect(geometry.loads, 1);
    });

    testWidgets('walk-only: the ends and MRT, no connectors, no legend', (
      tester,
    ) async {
      await pumpApp(tester, app());
      // Bishan MRT (NS17) is about 30 m from the fake fix: walk-only.
      await pickDestination(tester, 'Bishan MRT', 'BISHAN MRT STATION (NS17)');
      await openMap(tester);
      await tester.pump();
      expect(marker('origin'), findsOneWidget);
      expect(marker('destination'), findsOneWidget);
      expect(marker('mrtNearOrigin'), findsOneWidget);
      expect(find.byKey(connectors), findsNothing);
      expect(find.byKey(legend), findsNothing);
    });

    testWidgets('no direct bus: the ends and MRT, no connectors, no legend', (
      tester,
    ) async {
      // Tampines Hub → ION Orchard: no fake service connects them.
      await pumpApp(tester, app(at: tampinesHub.position));
      await pickDestination(tester, 'ION Orchard', 'ION ORCHARD');
      expect(find.byKey(const Key('journey-no-direct')), findsOneWidget);
      await openMap(tester);
      await tester.pump();
      expect(marker('boarding'), findsNothing);
      expect(
        find.byTooltip('Nearest MRT: TAMPINES MRT STATION'),
        findsOneWidget,
      );
      expect(
        find.byTooltip('Near your destination: ORCHARD MRT STATION'),
        findsOneWidget,
      );
      expect(find.byKey(connectors), findsNothing);
      expect(find.byKey(legend), findsNothing);
      expect(geometry.loads, 0);
    });

    testWidgets('legend: the bus and walk entries, nothing for MRT', (
      tester,
    ) async {
      await pumpApp(tester, app());
      await pickDestination(tester, 'VivoCity', 'VIVOCITY');
      await openMap(tester);
      await tester.pump();
      expect(JourneyMap.busLegend('F20'), 'Bus F20 route');
      expect(JourneyMap.walkLegend, 'Walk (straight-line estimate)');
      expect(inLegend('Bus F20 route'), findsOneWidget);
      expect(inLegend(JourneyMap.walkLegend), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(legend),
          matching: find.textContaining('MRT'),
        ),
        findsNothing,
      );
      await selectOption(tester, 'F10');
      expect(inLegend('Bus F10 route'), findsOneWidget);
    });

    testWidgets('dark mode: the same connectors, pins and legend', (
      tester,
    ) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await pumpApp(tester, app());
      await pickDestination(tester, 'VivoCity', 'VIVOCITY');
      await openMap(tester);
      await tester.pump();
      expect(
        tester.widget<PolylineLayer>(find.byKey(connectors)).polylines,
        hasLength(2),
      );
      expect(marker('mrtNearOrigin'), findsOneWidget);
      expect(inLegend(JourneyMap.walkLegend), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('2× text at 360 dp: the legend wraps without overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 6000);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(app());
      await tester.pump();
      await pickDestination(tester, 'VivoCity', 'VIVOCITY');
      await openMap(tester);
      await tester.pump();
      expect(inLegend(JourneyMap.busLegend('F20')), findsOneWidget);
      expect(inLegend(JourneyMap.walkLegend), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('selecting an option refits the camera the user had moved '
        'away (once per scene change)', (tester) async {
      await pumpApp(tester, app());
      await pickDestination(tester, 'VivoCity', 'VIVOCITY');
      await openMap(tester);
      await tester.pump();
      LatLngBounds visible() =>
          MapCamera.of(tester.element(find.byType(MarkerLayer))).visibleBounds;
      // Pan far east: the journey leaves the view.
      for (var i = 0; i < 4; i++) {
        await tester.drag(find.byType(FlutterMap), const Offset(-600, 0));
        await tester.pump();
      }
      final viv1 = _toMap(stops['VIV1']!.position);
      expect(visible().contains(viv1), isFalse, reason: 'precondition: moved');
      await selectOption(tester, 'F10');
      for (final code in ['BSH1', 'MID1', 'MID2', 'VIV1']) {
        expect(
          visible().contains(_toMap(stops[code]!.position)),
          isTrue,
          reason: code,
        );
      }
    });

    // A guard, not a regression test: on flutter_map 8.3.2 a scene change
    // cannot land before onMapReady (see the ledger / docs), so this passes on
    // the pre-P2-M3 code too. It pins that the latest scene is the one fitted.
    testWidgets('a selection made as the map opens is the one the camera '
        'fits (the latest scene, not the first)', (tester) async {
      await pumpApp(tester, app());
      await pickDestination(tester, 'VivoCity', 'VIVOCITY');
      await tester.tap(find.byKey(showMap));
      await tester.pump(); // the map's first frame
      await selectOption(tester, 'F30');
      final visible = MapCamera.of(tester.element(find.byType(MarkerLayer)))
          .visibleBounds;
      for (final code in ['BSH1', 'ION1', 'MID2', 'VIV1']) {
        expect(
          visible.contains(_toMap(stops[code]!.position)),
          isTrue,
          reason: code,
        );
      }
    });
  });

  group('reduced motion (P2-M4)', () {
    MapCamera camera(WidgetTester tester) =>
        MapCamera.of(tester.element(find.byType(MarkerLayer)));

    InteractionOptions gestures(WidgetTester tester) => tester
        .widget<FlutterMap>(find.byType(FlutterMap))
        .options
        .interactionOptions;

    /// The system's reduce-motion setting as the engine reports it (Android
    /// "Remove animations", Web prefers-reduced-motion). It reaches both
    /// MediaQuery and the framework's own animation scaling.
    void setReduceMotion(WidgetTester tester, bool on) {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(disableAnimations: on);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
    }

    Future<void> openJourneyMap(WidgetTester tester) async {
      await pumpApp(tester, app());
      await pickDestination(tester, 'VivoCity', 'VIVOCITY');
      await openMap(tester);
      await tester.pump();
    }

    /// Two taps on an empty part of the map: near its top-left corner, which
    /// the fitted camera keeps clear of every pin (MapConfig.fitPadding).
    Future<void> doubleTapMap(WidgetTester tester) async {
      final spot =
          tester.getTopLeft(find.byType(FlutterMap)) + const Offset(12, 12);
      await tester.tapAt(spot);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(spot);
    }

    /// A quick swipe, well over flutter_map's 800 px/s fling threshold.
    Future<void> swipeMap(WidgetTester tester) =>
        tester.fling(find.byType(FlutterMap), const Offset(-300, 0), 2000);

    const allButRotate = InteractiveFlag.all & ~InteractiveFlag.rotate;

    testWidgets('the gestures follow the reduce-motion setting: no fling and '
        'an instant double-tap zoom while it is on, flutter_map\'s defaults '
        'otherwise; every other gesture stays on', (tester) async {
      await openJourneyMap(tester);
      expect(gestures(tester).flags, allButRotate);
      expect(
        gestures(tester).doubleTapZoomDuration,
        const InteractionOptions().doubleTapZoomDuration,
      );

      setReduceMotion(tester, true);
      await tester.pump();
      expect(
        gestures(tester).flags,
        allButRotate & ~InteractiveFlag.flingAnimation,
      );
      expect(gestures(tester).doubleTapZoomDuration, Duration.zero);

      setReduceMotion(tester, false);
      await tester.pump();
      expect(gestures(tester).flags, allButRotate);
      expect(
        gestures(tester).doubleTapZoomDuration,
        const InteractionOptions().doubleTapZoomDuration,
      );
    });

    testWidgets('reduce motion: a swipe moves the map and it stops where the '
        'finger lifts; a double-tap zoom lands in the same frame', (
      tester,
    ) async {
      setReduceMotion(tester, true);
      await openJourneyMap(tester);
      final before = camera(tester).center;

      await swipeMap(tester);
      await tester.pump();
      final released = camera(tester).center;
      expect(released, isNot(before), reason: 'the drag itself still works');
      await tester.pump(const Duration(seconds: 1));
      expect(camera(tester).center, released, reason: 'no glide, no jump');

      final zoom = camera(tester).zoom;
      await doubleTapMap(tester);
      await tester.pump();
      expect(camera(tester).zoom, closeTo(zoom + 1, 1e-9));
    });

    // A guard, not a regression test: it passes before and after P2-M4. It
    // pins flutter_map's default motion when the setting is off, and shows
    // that the checks above can tell motion from none.
    testWidgets('without reduce motion: a swipe glides on after the finger '
        'lifts and a double-tap zoom animates (flutter_map\'s defaults)', (
      tester,
    ) async {
      await openJourneyMap(tester);
      await swipeMap(tester);
      await tester.pump();
      final released = camera(tester).center;
      await tester.pump(const Duration(seconds: 1));
      expect(camera(tester).center, isNot(released));

      final zoom = camera(tester).zoom;
      await doubleTapMap(tester);
      await tester.pump();
      expect(camera(tester).zoom, closeTo(zoom, 1e-9));
      await tester.pump(const Duration(milliseconds: 300));
      expect(camera(tester).zoom, closeTo(zoom + 1, 1e-9));
    });

    testWidgets('reduce motion switched on while the map is open (as '
        'designed, Q1): the camera stays where the user panned it, the next '
        'swipe stops where the finger lifts, a double-tap zoom lands within a '
        'frame, and the journey stays drawn', (tester) async {
      await openJourneyMap(tester);
      expect(find.byKey(const Key('map-ride-line')), findsOneWidget);
      // A slow pan (under the fling threshold), so the user's view differs
      // from the fitted one and a refit would show.
      await tester.timedDrag(
        find.byType(FlutterMap),
        const Offset(-200, 0),
        const Duration(seconds: 1),
      );
      await tester.pump();
      final panned = camera(tester);

      setReduceMotion(tester, true);
      await tester.pump();
      expect(camera(tester).center, panned.center, reason: 'no rebuild/refit');
      expect(camera(tester).zoom, panned.zoom, reason: 'no rebuild/refit');

      await swipeMap(tester);
      await tester.pump();
      final released = camera(tester).center;
      await tester.pump(const Duration(seconds: 1));
      expect(camera(tester).center, released);

      // As designed (P2-M4 Q1): the map is not rebuilt when the setting
      // changes, so it keeps the duration flutter_map fixed at creation, and
      // the framework plays it at 5 % (10 ms), within one frame. A map opened
      // with the setting on uses zero.
      final zoom = camera(tester).zoom;
      await doubleTapMap(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 17));
      expect(camera(tester).zoom, closeTo(zoom + 1, 1e-9));

      expect(find.byKey(const Key('map-ride-line')), findsOneWidget);
      expect(find.byKey(const Key('map-walk-connectors')), findsOneWidget);
      // The layer still holds every pin; flutter_map builds only those in
      // view, and the pans above moved some of them out of it.
      expect(
        tester
            .widget<MarkerLayer>(find.byType(MarkerLayer))
            .markers
            .map((m) => m.key),
        containsAll([
          const Key('map-marker-mrtNearOrigin'),
          const Key('map-marker-mrtNearDestination'),
        ]),
      );
      expect(geometry.loads, 1);
    });
  });
}

ll.LatLng _toMap(LatLng p) => ll.LatLng(p.latitude, p.longitude);
