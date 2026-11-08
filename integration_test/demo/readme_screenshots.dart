// Dev-only generator for the README screenshots (owner decision C-4,
// 2026-11-08). Not a test: its name does not end in _test.dart, so
// `flutter test integration_test` never runs it. On Web, with chromedriver on
// port 4444:
//
//   flutter drive --driver=test_driver/screenshot_driver.dart \
//     --target=integration_test/demo/readme_screenshots.dart \
//     -d web-server --browser-name=chrome --profile \
//     --browser-dimension=412x915@2
//
// The PNGs land in build/readme_screenshots/; copy them to docs/images/.
//
// The real app (unchanged `lib/`) over the integration tests' fakes: synthetic
// places, stops, services, arrivals and route line (integration_test/fakes/),
// with the origin side's names made synthetic too, and map tiles drawn on the
// device (an invented street grid, integration_test/fakes/synthetic_tiles.dart)
// instead of OneMap's. No network request is made
// for data, tiles or the OneMap logo. A strip at the top labels every
// screenshot as demonstration data.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sg_smart_commute/core/geo/geo.dart';
import 'package:sg_smart_commute/core/location/location_service.dart';
import 'package:sg_smart_commute/features/journey/data/mrt_asset.dart';
import 'package:sg_smart_commute/features/journey/data/mrt_asset_repository.dart';
import 'package:sg_smart_commute/features/journey/domain/bus_network.dart';
import 'package:sg_smart_commute/features/journey/domain/mrt.dart';

import '../fakes/fake_bus_network.dart';
import '../fakes/fake_environment_repository.dart';
import '../fakes/fake_location_service.dart';
import '../fakes/synthetic_tiles.dart';
import '../fakes/test_app.dart';
import '../support.dart';

/// The shared fakes keep real-sounding names on the origin side (the fake GPS
/// fix is at Bishan); the screenshots use synthetic ones.
const _renamed = {
  'Bishan Int (fake)': 'North Int (fake)',
  'Opp Bishan Stn (fake)': 'Opp North Stn (fake)',
  'BISHAN MRT STATION': 'FAKE NORTH MRT STATION',
};

BusNetwork _demoNetwork() {
  final n = fakeBusNetwork();
  return BusNetwork(
    stops: n.stops.map(
      (code, s) => MapEntry(
        code,
        BusStop(
          code: s.code,
          position: s.position,
          name: _renamed[s.name] ?? s.name,
          road: s.road,
        ),
      ),
    ),
    services: n.services,
  );
}

MrtAssetRepository _demoMrt() => MrtAssetRepository(
  load: () async => jsonEncode({
    'stations': encodeMrtStations([
      for (final s in fakeMrtStations)
        MrtStation(name: _renamed[s.name] ?? s.name, exits: s.exits),
    ]),
  }),
);

void main() {
  initIntegrationTest();

  testWidgets('README screenshots over synthetic data', (tester) async {
    final binding = IntegrationTestWidgetsFlutterBinding.instance;
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    await tester.pumpWidget(
      _DemoLabel(
        child: buildTestApp(
          location: FakeLocationService(
            access: LocationAccess.granted,
            position: const LatLng(1.3508, 103.8485),
          ),
          environment: FakeEnvironmentRepository(),
          busNetwork: FakeBusNetworkRepository(network: _demoNetwork()),
          mrt: _demoMrt(),
          mapTiles: SyntheticTileProvider.new,
        ),
      ),
    );
    await pumpUntilFound(tester, find.text('From: Current location'));
    await searchAndPick(
      tester,
      field: const Key('destination-field'),
      query: 'Bay Mall',
      result: 'BAY MALL (fake)',
    );
    await pumpUntilFound(tester, find.byKey(const Key('journey-suggested')));
    await pumpUntilFound(tester, find.textContaining('min'));

    // 1. The route card at the top, then the journey card.
    await _scrollToTop(tester, find.text('From: Current location'));
    await _settle(tester);
    await binding.takeScreenshot('app-light');

    // 2. and 3. The map, fitted to the journey, light then dark.
    await scrollToAndTap(tester, find.byKey(const Key('show-map')));
    await pumpUntilFound(tester, find.byKey(const Key('map-ride-line')));
    await _scrollToBottom(tester, find.byKey(const Key('hide-map')));
    await _settle(tester);
    await binding.takeScreenshot('journey-map-light');

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await scrollToAndTap(tester, find.byKey(const Key('hide-map')));
    await scrollToAndTap(tester, find.byKey(const Key('show-map')));
    await pumpUntilFound(tester, find.byKey(const Key('map-ride-line')));
    await _scrollToBottom(tester, find.byKey(const Key('hide-map')));
    await _settle(tester);
    await binding.takeScreenshot('journey-map-dark');
    tester.platformDispatcher.clearPlatformBrightnessTestValue();
  });
}

/// Scrolls the home list so [target]'s top sits [above] px below the app bar.
Future<void> _scrollToTop(
  WidgetTester tester,
  Finder target, {
  double above = 16,
}) async {
  await tester.ensureVisible(target);
  await tester.pump();
  final appBarBottom = tester.getBottomLeft(find.byType(AppBar)).dy;
  final dy = tester.getTopLeft(target).dy - appBarBottom - above;
  await tester.drag(find.byType(Scrollable).first, Offset(0, -dy));
  await tester.pump(const Duration(milliseconds: 300));
}

/// Scrolls so the card holding [inCard] ends 16 px above the window's bottom:
/// the journey card shows above the map, and nothing below it.
Future<void> _scrollToBottom(WidgetTester tester, Finder inCard) async {
  final card = find.ancestor(of: inCard, matching: find.byType(Card)).first;
  await tester.ensureVisible(card);
  await tester.pump();
  final bottom = tester.view.physicalSize.height / tester.view.devicePixelRatio;
  final dy = tester.getBottomLeft(card).dy - (bottom - 16);
  await tester.drag(find.byType(Scrollable).first, Offset(0, -dy));
  await tester.pump(const Duration(milliseconds: 300));
}

/// Live frames for long enough to decode the tiles and finish any animation.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The "demonstration data" strip above the app.
class _DemoLabel extends StatelessWidget {
  const _DemoLabel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: Column(
      children: [
        Container(
          width: double.infinity,
          color: const Color(0xFF5B2A86),
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
          child: const Text(
            'DEMONSTRATION DATA · synthetic places, stops, arrivals and map',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFFFFFFFF),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(child: child),
      ],
    ),
  );
}
