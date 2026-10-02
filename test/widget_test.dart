// Widget tests for the Milestone 1 home screen (guide v2.1 §18). Location and
// environment are fakes; no test calls a live API. Time is the test binding's
// fake clock, so the 10 s timeout never waits in real time.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/core/errors/app_failure.dart';
import 'package:sg_smart_commute/core/geo/geo.dart';
import 'package:sg_smart_commute/core/location/location_service.dart';
import 'package:sg_smart_commute/features/origin/domain/origin_controller.dart';
import 'package:sg_smart_commute/features/origin/presentation/origin_card.dart';

import 'fakes/fake_environment_repository.dart';
import 'fakes/fake_location_service.dart';
import 'fakes/test_app.dart';

const bishan = LatLng(1.3508, 103.8485);
const mountainView = LatLng(37.4220, -122.0841);

Finder tile(String key) => find.byKey(Key(key));

Finder inTile(String key, String text) =>
    find.descendant(of: tile(key), matching: find.text(text));

/// Types [query] into a place-search field, waits out the debounce and taps
/// the result named [result]. Nothing is selected without the tap.
Future<void> searchAndPick(
  WidgetTester tester,
  String query,
  String result, {
  Key field = const Key('manual-origin-field'),
}) async {
  await tester.enterText(find.byKey(field), query);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
  final hit = find.text(result);
  await tester.ensureVisible(hit);
  await tester.pump();
  await tester.tap(hit);
  await tester.pump();
}

/// Pumps [app] on a tall test screen, so every card stays built. The home
/// screen is a lazy list; after scrolling to a search result and selecting
/// it, a short default screen could leave the origin card unbuilt.
Future<void> pumpApp(WidgetTester tester, Widget app) async {
  tester.view.physicalSize = const Size(1080, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
}

const tampinesHubLine = 'From: OUR TAMPINES HUB (chosen manually)';

void main() {
  late FakeLocationService location;
  late FakeEnvironmentRepository env;

  setUp(() => env = FakeEnvironmentRepository());

  testWidgets('initial loading: shell renders before location resolves', (
    tester,
  ) async {
    location = FakeLocationService();
    await pumpApp(tester, buildTestApp(location: location, environment: env));

    expect(find.text('Singapore Smart Commute'), findsOneWidget);
    expect(find.text('Checking location permission…'), findsOneWidget);
    expect(find.text('Loading 24-hr PSI…'), findsOneWidget);

    await tester.pump();
    // National UV doesn't need a position; area/region tiles wait for one.
    expect(inTile('tile-uv', 'UV 7 (High)'), findsOneWidget);
    expect(inTile('tile-psi', 'Waiting for your location'), findsOneWidget);
    // All four datasets are fetched at launch, once each.
    expect(env.calls, {'forecast': 1, 'uv': 1, 'pm25': 1, 'psi': 1});
  });

  testWidgets('GPS in Singapore → dashboard with scope and timestamp', (
    tester,
  ) async {
    location = FakeLocationService(
      access: LocationAccess.granted,
      position: bishan,
    );
    await pumpApp(tester, buildTestApp(location: location, environment: env));
    await tester.pump();
    await tester.pump();

    expect(find.text('From: Current location (from GPS)'), findsOneWidget);

    expect(inTile('tile-forecast', 'Partly Cloudy (Day)'), findsOneWidget);
    expect(inTile('tile-forecast', 'Bishan area'), findsOneWidget);
    expect(inTile('tile-uv', 'Singapore (national)'), findsOneWidget);
    expect(inTile('tile-pm25', '1-hr PM2.5 18 µg/m³ (Normal)'), findsOneWidget);
    expect(inTile('tile-pm25', 'Central region'), findsOneWidget);
    expect(inTile('tile-psi', '24-hr PSI 54 (Moderate)'), findsOneWidget);
    expect(inTile('tile-psi', 'Central region'), findsOneWidget);
    expect(inTile('tile-psi', 'As of 12:00 SGT · 12 min ago'), findsOneWidget);
    // PSI and PM2.5 never share a tile or a label.
    expect(
      find.descendant(
        of: tile('tile-psi'),
        matching: find.textContaining('PM2.5'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: tile('tile-pm25'),
        matching: find.textContaining('PSI'),
      ),
      findsNothing,
    );
    expect(find.text('Stale'), findsNothing);
  });

  testWidgets('permission denied → manual origin prompt immediately', (
    tester,
  ) async {
    location = FakeLocationService(access: LocationAccess.denied);
    await pumpApp(tester, buildTestApp(location: location, environment: env));
    await tester.pump();

    expect(find.text(OriginCard.fallbackPrompt), findsOneWidget);
    expect(find.text('Location permission was not granted.'), findsOneWidget);
    expect(find.byKey(const Key('manual-origin-field')), findsOneWidget);
    expect(location.positionRequests, 0);
  });

  testWidgets('permanently denied → "Open settings" action', (tester) async {
    location = FakeLocationService(access: LocationAccess.deniedForever);
    await pumpApp(tester, buildTestApp(location: location, environment: env));
    await tester.pump();

    expect(find.text(OriginCard.fallbackPrompt), findsOneWidget);
    await tester.tap(find.text('Open settings'));
    await tester.pump();
    expect(location.settingsOpened, [LocationAccess.deniedForever]);
  });

  testWidgets('granted → no fix within 10 s → manual origin', (tester) async {
    location = FakeLocationService(access: LocationAccess.granted);
    await pumpApp(tester, buildTestApp(location: location, environment: env));
    await tester.pump();
    expect(find.text('Finding your location…'), findsOneWidget);

    await tester.pump(const Duration(seconds: 9));
    expect(find.text(OriginCard.fallbackPrompt), findsNothing);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text(OriginCard.fallbackPrompt), findsOneWidget);
    expect(find.text('Finding your location took too long.'), findsOneWidget);
  });

  testWidgets('out-of-Singapore fix → manual origin', (tester) async {
    location = FakeLocationService(
      access: LocationAccess.granted,
      position: mountainView,
    );
    await pumpApp(tester, buildTestApp(location: location, environment: env));
    await tester.pump();
    await tester.pump();

    expect(find.text(OriginCard.fallbackPrompt), findsOneWidget);
    expect(
      find.text('Your reported location is outside Singapore.'),
      findsOneWidget,
    );
    expect(inTile('tile-psi', 'Waiting for your location'), findsOneWidget);
  });

  testWidgets('a searched manual origin drives the area/region tiles', (
    tester,
  ) async {
    location = FakeLocationService(access: LocationAccess.denied);
    await pumpApp(tester, buildTestApp(location: location, environment: env));
    await tester.pump();

    await searchAndPick(tester, 'Tampines Hub', 'OUR TAMPINES HUB');

    expect(find.text(tampinesHubLine), findsOneWidget);
    expect(inTile('tile-forecast', 'Thundery Showers'), findsOneWidget);
    expect(inTile('tile-forecast', 'Tampines area'), findsOneWidget);
    expect(inTile('tile-psi', '24-hr PSI 61 (Moderate)'), findsOneWidget);
    expect(inTile('tile-psi', 'East region'), findsOneWidget);
    expect(inTile('tile-pm25', '1-hr PM2.5 13 µg/m³ (Normal)'), findsOneWidget);
  });

  testWidgets('late GPS fix does not overwrite a manual origin', (
    tester,
  ) async {
    location = FakeLocationService(access: LocationAccess.granted);
    await pumpApp(tester, buildTestApp(location: location, environment: env));
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));
    expect(find.text(OriginCard.fallbackPrompt), findsOneWidget);

    await searchAndPick(tester, 'Tampines Hub', 'OUR TAMPINES HUB');
    location.fix(bishan); // arrives late
    await tester.pump();

    expect(find.text(tampinesHubLine), findsOneWidget);
    expect(inTile('tile-forecast', 'Tampines area'), findsOneWidget);
    expect(find.byKey(const Key('use-current-location')), findsOneWidget);

    // Only an explicit tap switches to GPS.
    await tester.tap(find.byKey(const Key('use-current-location')));
    await tester.pump();
    expect(find.text('From: Current location (from GPS)'), findsOneWidget);
    expect(inTile('tile-forecast', 'Bishan area'), findsOneWidget);
  });

  testWidgets('retry with a manual origin: only the chip switches to GPS', (
    tester,
  ) async {
    location = FakeLocationService(access: LocationAccess.granted);
    await pumpApp(tester, buildTestApp(location: location, environment: env));
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));
    await searchAndPick(tester, 'Tampines Hub', 'OUR TAMPINES HUB');

    // Attempt B runs while the manual origin is set; A answers late too.
    location.reset();
    ProviderScope.containerOf(tester.element(find.byType(OriginCard)))
        .read(originControllerProvider.notifier)
        .retryLocation();
    location.grant();
    await tester.pump();
    location.fixAttempt(0, mountainView);
    location.fix(bishan);
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));

    expect(find.text(tampinesHubLine), findsOneWidget);
    expect(inTile('tile-forecast', 'Tampines area'), findsOneWidget);
    await tester.tap(find.byKey(const Key('use-current-location')));
    await tester.pump();
    expect(find.text('From: Current location (from GPS)'), findsOneWidget);
    expect(inTile('tile-forecast', 'Bishan area'), findsOneWidget);
  });

  testWidgets('late GPS fix while typing is offered, not applied', (
    tester,
  ) async {
    location = FakeLocationService(access: LocationAccess.granted);
    await pumpApp(tester, buildTestApp(location: location, environment: env));
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));

    await tester.enterText(
      find.byKey(const Key('manual-origin-field')),
      'Tampines Hub',
    );
    await tester.pump(const Duration(milliseconds: 400));
    location.fix(bishan);
    await tester.pump();

    expect(find.text(OriginCard.fallbackPrompt), findsOneWidget);
    expect(find.text('OUR TAMPINES HUB'), findsOneWidget); // still choosable
    expect(find.byKey(const Key('use-current-location')), findsOneWidget);
  });

  testWidgets('a failing dataset shows Retry without hiding the others', (
    tester,
  ) async {
    env.failPsi = const NetworkUnavailable();
    location = FakeLocationService(
      access: LocationAccess.granted,
      position: bishan,
    );
    await pumpApp(tester, buildTestApp(location: location, environment: env));
    await tester.pump();
    await tester.pump();

    expect(
      inTile('tile-psi', const NetworkUnavailable().message),
      findsOneWidget,
    );
    expect(inTile('tile-psi', '24-hr PSI 54 (Moderate)'), findsNothing);
    expect(inTile('tile-pm25', '1-hr PM2.5 18 µg/m³ (Normal)'), findsOneWidget);

    env.failPsi = null;
    final retry = find.descendant(
      of: tile('tile-psi'),
      matching: find.text('Retry'),
    );
    await tester.ensureVisible(retry);
    await tester.pump();
    await tester.tap(retry);
    await tester.pump();
    await tester.pump();
    expect(inTile('tile-psi', '24-hr PSI 54 (Moderate)'), findsOneWidget);
    expect(env.calls['psi'], 2);
    expect(env.calls['pm25'], 1); // Retry is per dataset.
  });

  testWidgets('a failed refresh keeps the previous reading and its time', (
    tester,
  ) async {
    var now = fakeNow;
    location = FakeLocationService(
      access: LocationAccess.granted,
      position: bishan,
    );
    await pumpApp(
      tester,
      buildTestApp(location: location, environment: env, clock: () => now),
    );
    await tester.pump();
    await tester.pump();
    expect(inTile('tile-psi', '24-hr PSI 54 (Moderate)'), findsOneWidget);
    const asOf = 'As of 12:00 SGT · 12 min ago';
    expect(inTile('tile-psi', asOf), findsOneWidget);

    env.failPsi = const NetworkUnavailable();
    await tester.tap(find.byKey(const Key('refresh-conditions')));
    await tester.pump();
    await tester.pump();

    // The earlier reading and its timestamp stay; the failure is added.
    expect(inTile('tile-psi', '24-hr PSI 54 (Moderate)'), findsOneWidget);
    expect(inTile('tile-psi', asOf), findsOneWidget);
    final failed = find.descendant(
      of: tile('tile-psi'),
      matching: find.byKey(const Key('refresh-failed')),
    );
    expect(failed, findsOneWidget);
    expect(
      find.descendant(
        of: failed,
        matching: find.text(
          "Couldn't refresh: ${const NetworkUnavailable().message}",
        ),
      ),
      findsOneWidget,
    );

    // Retry recovers and removes the failure line.
    env.failPsi = null;
    final retry = find.descendant(of: failed, matching: find.text('Retry'));
    await tester.ensureVisible(retry);
    await tester.pump();
    await tester.tap(retry);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('refresh-failed')), findsNothing);
    expect(inTile('tile-psi', '24-hr PSI 54 (Moderate)'), findsOneWidget);
    expect(env.calls['psi'], 3);
  });

  testWidgets('stale readings are marked, not replaced', (tester) async {
    location = FakeLocationService(
      access: LocationAccess.granted,
      position: bishan,
    );
    await pumpApp(
      tester,
      buildTestApp(
        location: location,
        environment: env,
        clock: () => fakeNow.add(const Duration(hours: 3)),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(inTile('tile-psi', '24-hr PSI 54 (Moderate)'), findsOneWidget);
    expect(inTile('tile-psi', 'Stale'), findsOneWidget);
    expect(inTile('tile-pm25', 'Stale'), findsOneWidget);
  });

  testWidgets('refresh refetches all four, then is throttled', (tester) async {
    var now = fakeNow;
    location = FakeLocationService(
      access: LocationAccess.granted,
      position: bishan,
    );
    await pumpApp(
      tester,
      buildTestApp(location: location, environment: env, clock: () => now),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('refresh-conditions')));
    await tester.pump();
    expect(env.calls, {'forecast': 2, 'uv': 2, 'pm25': 2, 'psi': 2});

    now = now.add(const Duration(seconds: 5));
    await tester.tap(find.byKey(const Key('refresh-conditions')));
    await tester.pump();
    expect(env.calls['psi'], 2);
    expect(
      find.text('Conditions were just updated. Try again shortly.'),
      findsOneWidget,
    );

    now = now.add(const Duration(seconds: 15));
    await tester.tap(find.byKey(const Key('refresh-conditions')));
    await tester.pump();
    expect(env.calls['psi'], 3);
  });
}
