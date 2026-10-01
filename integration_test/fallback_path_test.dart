// Phase 1 fallback/error-path integration test (guide v2.1 §18, item 2),
// M1–M3: permission denied (or a fix outside Singapore, or a timeout) → the
// manual origin prompt appears → the user searches for and selects an origin
// → searches for and selects a destination → "No direct bus found" plus the
// MRT alternative (fake bus network and MRT asset) → a provider fails (24-hr
// PSI throws NetworkUnavailable) → a clear error with Retry and no
// fabricated value → Retry with the recovered fake succeeds.
//
// M4 extends the failure step to bus arrival. Every provider is a fake; no
// live API is called. The 10 s timeout is injected (short), so the test never
// waits 10 s in real time.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sg_smart_commute/core/errors/app_failure.dart';
import 'package:sg_smart_commute/core/geo/geo.dart';
import 'package:sg_smart_commute/core/location/location_service.dart';
import 'package:sg_smart_commute/features/destination/presentation/destination_card.dart';
import 'package:sg_smart_commute/features/origin/presentation/origin_card.dart';

import '../test/fakes/fake_environment_repository.dart';
import '../test/fakes/fake_location_service.dart';
import '../test/fakes/test_app.dart';
import 'support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('permission denied → search origin → search destination → '
      'provider failure → Retry recovers', (tester) async {
    final location = FakeLocationService(access: LocationAccess.denied);
    final env = FakeEnvironmentRepository()
      ..failPsi = const NetworkUnavailable();
    await tester.pumpWidget(buildTestApp(location: location, environment: env));

    // Manual prompt immediately; no position was ever requested.
    await pumpUntilFound(tester, find.text(OriginCard.fallbackPrompt));
    expect(location.positionRequests, 0);

    await searchAndPick(
      tester,
      field: const Key('manual-origin-field'),
      query: 'Tampines Hub',
      result: 'OUR TAMPINES HUB',
    );
    await pumpUntilFound(
      tester,
      find.text('From: OUR TAMPINES HUB (chosen manually)'),
    );

    // M2: destination search after the manual origin.
    await pumpUntilFound(tester, find.text(DestinationCard.prompt));
    await searchAndPick(
      tester,
      field: const Key('destination-field'),
      query: '238801',
      result: 'ION ORCHARD',
    );
    await pumpUntilFound(tester, find.text('To: ION ORCHARD'));
    expect(
      find.text('From: OUR TAMPINES HUB (chosen manually)'),
      findsOneWidget,
    );

    // M3: no single fake service connects Tampines Hub and ION Orchard.
    await pumpUntilFound(tester, find.byKey(const Key('journey-no-direct')));
    expect(find.text('No direct bus found'), findsOneWidget);
    expect(find.textContaining('Take Bus'), findsNothing);
    final mrt = find.byKey(const Key('journey-mrt'));
    await tester.ensureVisible(mrt);
    await tester.pump();
    expect(
      find.descendant(
        of: mrt,
        matching: find.textContaining('Nearest MRT: TAMPINES MRT STATION'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: mrt,
        matching: find.textContaining(
          'Near your destination: ORCHARD MRT STATION',
        ),
      ),
      findsOneWidget,
    );

    await pumpUntilFound(tester, inTile('tile-forecast', 'Tampines area'));

    // PSI failed: clear message + Retry, and no PSI value is shown.
    final error = inTile('tile-psi', const NetworkUnavailable().message);
    await tester.ensureVisible(error);
    await tester.pump();
    expect(error, findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('tile-psi')),
        matching: find.textContaining('24-hr PSI '),
      ),
      findsNothing,
    );
    // The other region tile is unaffected.
    expect(inTile('tile-pm25', '1-hr PM2.5 13 µg/m³ (Normal)'), findsOneWidget);

    // Recover and retry.
    env.failPsi = null;
    await scrollToAndTap(
      tester,
      find.descendant(
        of: find.byKey(const Key('tile-psi')),
        matching: find.text('Retry'),
      ),
    );
    await pumpUntilFound(tester, inTile('tile-psi', '24-hr PSI 61 (Moderate)'));
    expect(inTile('tile-psi', 'East region'), findsOneWidget);
    expect(env.calls['psi'], 2);
  });

  testWidgets('fix outside Singapore → manual origin', (tester) async {
    await tester.pumpWidget(
      buildTestApp(
        location: FakeLocationService(
          access: LocationAccess.granted,
          position: const LatLng(37.4220, -122.0841), // emulator default
        ),
        environment: FakeEnvironmentRepository(),
      ),
    );
    await pumpUntilFound(tester, find.text(OriginCard.fallbackPrompt));
    expect(
      find.text('Your reported location is outside Singapore.'),
      findsOneWidget,
    );
  });

  testWidgets('no fix before the (injected) timeout → manual origin, '
      'and the late fix does not overwrite the manual choice', (tester) async {
    final location = FakeLocationService(access: LocationAccess.granted);
    await tester.pumpWidget(
      buildTestApp(
        location: location,
        environment: FakeEnvironmentRepository(),
        locationTimeout: const Duration(milliseconds: 200),
      ),
    );
    await pumpUntilFound(tester, find.text(OriginCard.fallbackPrompt));
    expect(find.text('Finding your location took too long.'), findsOneWidget);

    await searchAndPick(
      tester,
      field: const Key('manual-origin-field'),
      query: 'ION Orchard',
      result: 'ION ORCHARD',
    );
    location.fix(const LatLng(1.3508, 103.8485)); // late, valid
    await pumpUntilFound(tester, find.byKey(const Key('use-current-location')));
    expect(find.text('From: ION ORCHARD (chosen manually)'), findsOneWidget);
  });
}
