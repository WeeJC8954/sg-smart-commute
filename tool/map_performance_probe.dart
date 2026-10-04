// Dev-only probe (P2-M4, docs/testing.md): frame timings of the open journey
// map on an Android device or emulator, in profile mode. Not part of the app
// and not a test gate; `flutter test` never runs it:
//
//   flutter drive --profile --keep-app-running -d <android-device> \
//     --driver=test_driver/integration_test.dart \
//     --target=tool/map_performance_probe.dart
//
// Without --keep-app-running, flutter drive uninstalls the app at the end,
// and the tile cache goes with it, so a second run would start cold.
//
// The journey is the integration tests' fake one (GPS at Bishan, a direct bus
// to VivoCity with its ride line, both walking connectors and both MRT pins),
// but the tiles are live OneMap tiles through the app's OneMapTileProvider, so
// tile decoding and drawing are measured too. Only the tiles of the map on
// screen are requested: the fitted view and what the scripted pans reveal, in
// light and then dark mode (docs/map-feasibility.md §4.2). Android only: it
// imports the shared fakes from integration_test/, which a Web build cannot.
// The results (FrameTimingSummarizer's summary per mode, plus p95, which it
// does not compute) land in build/integration_response_data.json.
import 'dart:ui' show FrameTiming;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sg_smart_commute/core/geo/geo.dart';
import 'package:sg_smart_commute/core/location/location_service.dart';
import 'package:sg_smart_commute/features/map/presentation/basemap.dart';

import '../integration_test/fakes/fake_environment_repository.dart';
import '../integration_test/fakes/fake_location_service.dart';
import '../integration_test/fakes/test_app.dart';
import '../integration_test/support.dart';

void main() {
  initIntegrationTest();

  testWidgets('journey map frame timings, light then dark', (tester) async {
    final binding = IntegrationTestWidgetsFlutterBinding.instance;
    // Frames come from the engine as in the app, not only on pump.
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    await tester.pumpWidget(
      buildTestApp(
        location: FakeLocationService(
          access: LocationAccess.granted,
          position: const LatLng(1.3508, 103.8485), // Bishan
        ),
        environment: FakeEnvironmentRepository(),
        mapTiles: OneMapTileProvider.new,
      ),
    );
    await pumpUntilFound(tester, find.text('From: Current location'));
    await searchAndPick(
      tester,
      field: const Key('destination-field'),
      query: 'VivoCity',
      result: 'VIVOCITY',
    );
    await pumpUntilFound(tester, find.byKey(const Key('journey-suggested')));
    await scrollToAndTap(tester, find.byKey(const Key('show-map')));
    await pumpUntilFound(tester, find.byKey(const Key('map-ride-line')));

    final report = <String, Object?>{};
    for (final mode in [Brightness.light, Brightness.dark]) {
      tester.platformDispatcher.platformBrightnessTestValue = mode;
      // Back to the fitted view, then give this style's first tiles time.
      await scrollToAndTap(tester, find.byKey(const Key('hide-map')));
      await scrollToAndTap(tester, find.byKey(const Key('show-map')));
      await pumpUntilFound(tester, find.byKey(const Key('map-ride-line')));
      for (final key in [
        'map-walk-connectors',
        'map-marker-mrtNearOrigin',
        'map-marker-mrtNearDestination',
      ]) {
        expect(find.byKey(Key(key)), findsOneWidget, reason: key);
      }
      await tester.ensureVisible(find.byType(FlutterMap));
      await tester.pump(const Duration(seconds: 3));
      report[mode.name] = await _measure(tester);
    }
    tester.platformDispatcher.clearPlatformBrightnessTestValue();
    binding.reportData = report;
  });
}

/// Four pans around the journey, twice (each 600 ms long, like a finger), then
/// a double-tap zoom; every frame drawn meanwhile is summarised.
Future<Map<String, Object?>> _measure(WidgetTester tester) async {
  final frames = <FrameTiming>[];
  void record(List<FrameTiming> timings) => frames.addAll(timings);
  tester.binding.addTimingsCallback(record);

  final map = find.byType(FlutterMap);
  for (var round = 0; round < 2; round++) {
    for (final pan in const [
      Offset(-250, 0),
      Offset(0, -200),
      Offset(250, 0),
      Offset(0, 200),
    ]) {
      await tester.timedDrag(map, pan, const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 400));
    }
  }
  // An empty corner of the map (the fitted camera keeps pins clear of it).
  final spot = tester.getTopLeft(map) + const Offset(12, 12);
  await tester.tapAt(spot);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tapAt(spot);
  await tester.pump(const Duration(seconds: 1));
  // The engine reports frame timings in batches, about once a second.
  await tester.pump(const Duration(seconds: 2));
  tester.binding.removeTimingsCallback(record);
  if (frames.isEmpty) throw StateError('no frame timings were reported');

  final summary = FrameTimingSummarizer(frames);
  // The same nearest-rank rule FrameTimingSummarizer uses for p90 and p99.
  double p95(List<Duration> times) {
    final sorted = [...times]..sort();
    return sorted[((sorted.length - 1) * 0.95).round()].inMicroseconds / 1e3;
  }

  return {
    ...summary.summary,
    '95th_percentile_frame_build_time_millis': p95(summary.frameBuildTime),
    '95th_percentile_frame_rasterizer_time_millis': p95(
      summary.frameRasterizerTime,
    ),
    'tiles_unavailable_note': find
        .byKey(const Key('map-tiles-unavailable'))
        .evaluate()
        .isNotEmpty,
  };
}
