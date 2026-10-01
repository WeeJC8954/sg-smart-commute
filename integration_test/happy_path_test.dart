// Phase 1 happy-path integration test (guide v2.1 §18, item 1), M1–M2:
// fake GPS inside Singapore → dashboard shows the fake forecast / UV /
// PM2.5 / PSI with scope labels and timestamps → the user searches for and
// selects a destination (fake place search).
//
// The direct bus → ETA → manual refresh steps are added by Milestones 3–4
// when those features exist. Every provider is a fake; no live API is called.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sg_smart_commute/core/geo/geo.dart';
import 'package:sg_smart_commute/core/location/location_service.dart';
import 'package:sg_smart_commute/features/destination/presentation/destination_card.dart';

import '../test/fakes/fake_environment_repository.dart';
import '../test/fakes/fake_location_service.dart';
import '../test/fakes/fake_place_search_repository.dart';
import '../test/fakes/test_app.dart';
import 'support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('GPS in Singapore → scoped environmental dashboard → '
      'search and select a destination', (tester) async {
    final env = FakeEnvironmentRepository();
    final places = FakePlaceSearchRepository();
    await tester.pumpWidget(
      buildTestApp(
        location: FakeLocationService(
          access: LocationAccess.granted,
          position: const LatLng(1.3508, 103.8485), // Bishan
        ),
        environment: env,
        places: places,
      ),
    );

    await pumpUntilFound(
      tester,
      find.text('From: Current location (from GPS)'),
    );

    // Forecast: area scope.
    await pumpUntilFound(tester, inTile('tile-forecast', 'Bishan area'));
    expect(inTile('tile-forecast', 'Partly Cloudy (Day)'), findsOneWidget);
    // UV: national scope.
    expect(inTile('tile-uv', 'UV 7 (High)'), findsOneWidget);
    expect(inTile('tile-uv', 'Singapore (national)'), findsOneWidget);

    // PM2.5 and PSI: region scope, separate tiles, separate labels.
    final pm25 = inTile('tile-pm25', '1-hr PM2.5 18 µg/m³ (Normal)');
    await tester.ensureVisible(pm25);
    await tester.pump();
    expect(pm25, findsOneWidget);
    expect(inTile('tile-pm25', 'Central region'), findsOneWidget);

    final psi = inTile('tile-psi', '24-hr PSI 54 (Moderate)');
    await tester.ensureVisible(psi);
    await tester.pump();
    expect(psi, findsOneWidget);
    expect(inTile('tile-psi', 'Central region'), findsOneWidget);
    expect(inTile('tile-psi', 'As of 12:00 SGT · 12 min ago'), findsOneWidget);

    // One fetch per dataset at launch.
    expect(env.calls, {'forecast': 1, 'uv': 1, 'pm25': 1, 'psi': 1});
    expect(find.byKey(const Key('manual-origin-field')), findsNothing);

    // M2: destination search (same component as the manual origin).
    await scrollToTop(tester);
    await pumpUntilFound(tester, find.text(DestinationCard.prompt));
    await searchAndPick(
      tester,
      field: const Key('destination-field'),
      query: 'VivoCity',
      result: 'VIVOCITY',
    );
    await pumpUntilFound(tester, find.text('To: VIVOCITY'));
    // Choosing a destination does not change the GPS origin.
    expect(find.text('From: Current location (from GPS)'), findsOneWidget);
    expect(places.queries, ['vivocity']);
  });
}
