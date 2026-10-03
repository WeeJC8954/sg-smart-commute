// P2-M1 widget tests: the optional journey map. Location, place search, bus
// data, tiles, the OneMap logo and the link launcher are all fakes
// (integration_test/fakes/), so no tile is fetched and no browser opened.
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/core/config/app_config.dart';
import 'package:sg_smart_commute/core/geo/geo.dart';
import 'package:sg_smart_commute/core/location/location_service.dart';
import 'package:sg_smart_commute/features/map/presentation/journey_map.dart';

import '../../../integration_test/fakes/fake_bus_arrival_repository.dart';
import '../../../integration_test/fakes/fake_bus_network.dart';
import '../../../integration_test/fakes/fake_environment_repository.dart';
import '../../../integration_test/fakes/fake_location_service.dart';
import '../../../integration_test/fakes/fake_map.dart';
import '../../../integration_test/fakes/fake_place_search_repository.dart';
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
  await tester.pump(const Duration(milliseconds: 400));
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

void main() {
  late FakeBusNetworkRepository bus;
  late FakeTileProvider tiles;
  late FakeLinkOpener links;

  setUp(() {
    bus = FakeBusNetworkRepository();
    tiles = FakeTileProvider();
    links = FakeLinkOpener();
  });

  Widget app({FakeTileProvider? tileProvider}) => buildTestApp(
    location: FakeLocationService(
      access: LocationAccess.granted,
      position: bishan,
    ),
    environment: FakeEnvironmentRepository(),
    places: FakePlaceSearchRepository(),
    busNetwork: bus,
    mrt: fakeMrtRepository(),
    busArrivals: FakeBusArrivalRepository(),
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
}
