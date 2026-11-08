// Dev-only entry point (owner approval 2026-11-08): the real app (unchanged
// `lib/`) over the integration tests' synthetic fakes, for manual TalkBack,
// keyboard and physical-device checks. Not a test: its name does not end in
// _test.dart, so `flutter test integration_test` never runs it. Android only
// (it imports the shared fakes, which a Web build cannot):
//
//   flutter build apk --debug -t integration_test/demo/synthetic_demo_app.dart //     -P syntheticTestBuild=true
//
// The flag (android/app/build.gradle.kts) gives it its own app id,
// sg.smartcommute.sg_smart_commute.synthetic, and the name "SSC Synthetic
// Test", so it installs beside the real app and keeps its own data. Gradle
// refuses this entry point without the flag, and the flag without it. The
// build overwrites build/app/outputs/flutter-apk/app-debug.apk; copy it away,
// then rebuild the real app with `flutter build apk --debug`.
//
// No network request: places, bus data, arrivals, route line, weather, map
// tiles (synthetic_tiles.dart) and the OneMap logo all come from the fakes.
// Links do not open a browser: every link answers "could not open", so the
// app shows "Couldn't open <host>." and a tester can see that it was
// activated. Location: GPS granted, fixed at the fakes' Bishan position. The
// clock is the fakes' fixed time, and the About dialog shows the fake version
// 9.8.7 (42), which identifies this build. Motion uses the app's real duration,
// so the system's reduce-motion setting can be checked.
import 'package:flutter/widgets.dart';
import 'package:sg_smart_commute/core/geo/geo.dart';
import 'package:sg_smart_commute/core/location/location_service.dart';
import 'package:sg_smart_commute/core/config/app_config.dart';

import '../fakes/fake_environment_repository.dart';
import '../fakes/fake_location_service.dart';
import '../fakes/synthetic_tiles.dart';
import '../fakes/test_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    buildTestApp(
      location: FakeLocationService(
        access: LocationAccess.granted,
        position: const LatLng(1.3508, 103.8485),
      ),
      environment: FakeEnvironmentRepository(),
      mapTiles: SyntheticTileProvider.new,
      openLink: (_) async => false,
      motionDuration: AppMotion.resize,
    ),
  );
}
