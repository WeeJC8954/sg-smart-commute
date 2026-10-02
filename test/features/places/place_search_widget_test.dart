// Milestone 2 widget tests: origin and destination place search (guide v2.1
// §5.3–§5.5, §8.3, §18). Location, environment and place search are fakes.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/core/config/app_config.dart';
import 'package:sg_smart_commute/core/errors/app_failure.dart';
import 'package:sg_smart_commute/core/geo/geo.dart';
import 'package:sg_smart_commute/core/location/location_service.dart';
import 'package:sg_smart_commute/features/destination/domain/destination_controller.dart';
import 'package:sg_smart_commute/features/destination/presentation/destination_card.dart';
import 'package:sg_smart_commute/features/origin/domain/origin.dart';
import 'package:sg_smart_commute/features/origin/domain/origin_controller.dart';
import 'package:sg_smart_commute/features/origin/presentation/origin_card.dart';
import 'package:sg_smart_commute/features/places/domain/place.dart';
import 'package:sg_smart_commute/features/places/presentation/place_search_field.dart';

import '../../fakes/fake_environment_repository.dart';
import '../../fakes/fake_location_service.dart';
import '../../fakes/fake_place_search_repository.dart';
import '../../fakes/test_app.dart';

const bishan = LatLng(1.3508, 103.8485);
const originField = Key('manual-origin-field');
const destinationField = Key('destination-field');

Future<void> pumpApp(WidgetTester tester, Widget app) async {
  tester.view.physicalSize = const Size(1080, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
  await tester.pump();
}

Future<void> type(WidgetTester tester, Key field, String text) async {
  await tester.enterText(find.byKey(field), text);
  await tester.pump(const Duration(milliseconds: 400)); // past the debounce
  await tester.pump();
}

Future<void> pick(WidgetTester tester, String result) async {
  await tester.tap(find.text(result));
  await tester.pump();
}

OriginState originOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(OriginCard)))
        .read(originControllerProvider);

DestinationState destinationOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(OriginCard)))
        .read(destinationControllerProvider);

void main() {
  late FakePlaceSearchRepository places;

  setUp(() => places = FakePlaceSearchRepository());

  Widget deniedApp() => buildTestApp(
    location: FakeLocationService(access: LocationAccess.denied),
    environment: FakeEnvironmentRepository(),
    places: places,
  );

  Widget gpsApp() => buildTestApp(
    location: FakeLocationService(
      access: LocationAccess.granted,
      position: bishan,
    ),
    environment: FakeEnvironmentRepository(),
    places: places,
  );

  testWidgets('location unavailable → search by postal code → select origin', (
    tester,
  ) async {
    await pumpApp(tester, deniedApp());
    expect(find.text(OriginCard.fallbackPrompt), findsOneWidget);
    expect(find.text(PlaceSearchField.hint), findsOneWidget);

    await type(tester, originField, '098585');
    expect(find.text('1 match. Tap it to confirm.'), findsOneWidget);
    expect(
      find.text('1 HARBOURFRONT WALK VIVOCITY SINGAPORE 098585'),
      findsOneWidget,
    );
    expect(find.text(oneMapAttribution), findsOneWidget);
    // A single exact match is still not selected until tapped.
    expect(originOf(tester).origin, isNull);

    await pick(tester, 'VIVOCITY');
    expect(find.text('From: VIVOCITY (chosen manually)'), findsOneWidget);
    final origin = originOf(tester).origin!;
    expect(origin.provenance, OriginProvenance.manual);
    expect(origin.position, vivoCity.position);
    expect(origin.detail, vivoCity.address);
  });

  testWidgets('ambiguous results are all listed and never auto-selected', (
    tester,
  ) async {
    await pumpApp(tester, deniedApp());
    await type(tester, originField, 'Bishan MRT');
    expect(find.text('2 matches. Choose the right one.'), findsOneWidget);
    expect(find.text('BISHAN MRT STATION (CC15)'), findsOneWidget);
    expect(find.text('BISHAN MRT STATION (NS17)'), findsOneWidget);
    // Address + postcode tell them apart.
    expect(find.textContaining('579842'), findsOneWidget);
    expect(find.textContaining('579827'), findsOneWidget);
    expect(originOf(tester).origin, isNull);

    await pick(tester, 'BISHAN MRT STATION (NS17)');
    expect(originOf(tester).origin!.position, bishanMrtNs.position);
  });

  testWidgets('an address identical to the name is not repeated', (
    tester,
  ) async {
    const hdb = '123 ANG MO KIO AVENUE 6 SINGAPORE 560123';
    places.results['123 ang mo kio ave 6'] = [
      fakePlace(
        hdb,
        lat: 1.3705,
        lng: 103.8443,
        address: hdb,
        postal: '560123',
        type: PlaceType.address,
      ),
    ];
    await pumpApp(tester, deniedApp());
    await type(tester, originField, 'Blk 123 Ang Mo Kio Ave 6');
    expect(find.text(hdb), findsOneWidget); // title only
    expect(find.text('560123'), findsOneWidget); // subtitle: the postcode

    // Neither card repeats it under the name either.
    await pick(tester, hdb);
    expect(find.text('From: $hdb (chosen manually)'), findsOneWidget);
    expect(find.text(hdb), findsNothing);
    expect(originOf(tester).origin!.detail, isNull);

    await type(tester, destinationField, 'Blk 123 Ang Mo Kio Ave 6');
    await pick(tester, hdb);
    expect(find.text('To: $hdb'), findsOneWidget);
    expect(find.text(hdb), findsNothing);
  });

  testWidgets('a distinct address is shown under the name in both cards', (
    tester,
  ) async {
    await pumpApp(tester, deniedApp());
    await type(tester, originField, 'VivoCity');
    await pick(tester, 'VIVOCITY');
    await type(tester, destinationField, 'ION Orchard');
    await pick(tester, 'ION ORCHARD');
    expect(find.text(vivoCity.address!), findsOneWidget);
    expect(find.text(ionOrchard.address!), findsOneWidget);
  });

  testWidgets('the search field accepts at most maxQueryLength characters', (
    tester,
  ) async {
    await pumpApp(tester, deniedApp());
    await tester.enterText(find.byKey(originField), 'x' * 500);
    await tester.pump();
    final field = tester.widget<TextField>(find.byKey(originField));
    expect(field.controller!.text.length, PlaceSearchConfig.maxQueryLength);
  });

  testWidgets('no results, too short, and the no-exact-postcode state', (
    tester,
  ) async {
    places.failures['640512'] = const NoExactPostalMatch('640512');
    await pumpApp(tester, deniedApp());

    await type(tester, originField, 'zz');
    expect(
      find.text('Type at least 3 characters, or a 6-digit postal code.'),
      findsOneWidget,
    );

    await type(tester, originField, 'Nowhere Lane');
    expect(
      find.textContaining('No places found for "Nowhere Lane"'),
      findsOneWidget,
    );

    await type(tester, originField, '640512');
    expect(find.textContaining('No exact match for 640512.'), findsOneWidget);
    expect(originOf(tester).origin, isNull);
  });

  testWidgets('OneMap token enforcement (401/403) shows a clear state, '
      'never a workaround', (tester) async {
    places.failures['vivocity'] = const ApiUnauthorized();
    await pumpApp(tester, deniedApp());
    await type(tester, originField, 'VivoCity');
    expect(
      find.text(placeSearchFailureMessage(const ApiUnauthorized())),
      findsOneWidget,
    );
    expect(find.textContaining('OneMap now requires sign-in'), findsOneWidget);
  });

  testWidgets('network failure → Retry recovers', (tester) async {
    places.failures['vivocity'] = const NetworkUnavailable();
    await pumpApp(tester, deniedApp());
    await type(tester, originField, 'VivoCity');
    expect(find.text(const NetworkUnavailable().message), findsOneWidget);

    places.failures.remove('vivocity');
    await tester.tap(
      find.descendant(
        of: find.byType(PlaceSearchField),
        matching: find.text('Retry'),
      ),
    );
    await tester.pump();
    expect(find.text('VIVOCITY'), findsOneWidget);
    expect(places.queries, ['vivocity', 'vivocity']);
  });

  testWidgets('destination prompt appears once an origin exists', (
    tester,
  ) async {
    await pumpApp(tester, deniedApp());
    expect(find.text(DestinationCard.prompt), findsNothing);

    await type(tester, originField, 'Tampines Hub');
    await pick(tester, 'OUR TAMPINES HUB');
    expect(find.text(DestinationCard.prompt), findsOneWidget);
  });

  testWidgets(
    'GPS origin → search and select a destination; origin unchanged',
    (tester) async {
      await pumpApp(tester, gpsApp());
      expect(find.text('From: Current location (from GPS)'), findsOneWidget);
      expect(find.text(DestinationCard.prompt), findsOneWidget);
      final before = originOf(tester).origin!;

      await type(tester, destinationField, 'ION Orchard');
      await pick(tester, 'ION ORCHARD');

      expect(find.text('To: ION ORCHARD'), findsOneWidget);
      expect(destinationOf(tester).place!.position, ionOrchard.position);
      final after = originOf(tester).origin!;
      expect(after.provenance, OriginProvenance.gps);
      expect(after.position, before.position);
      expect(after.label, before.label);
      expect(find.text('From: Current location (from GPS)'), findsOneWidget);
    },
  );

  testWidgets('changing an existing origin keeps the destination', (
    tester,
  ) async {
    await pumpApp(tester, deniedApp());
    await type(tester, originField, 'Tampines Hub');
    await pick(tester, 'OUR TAMPINES HUB');
    await type(tester, destinationField, 'VivoCity');
    await pick(tester, 'VIVOCITY');

    await tester.tap(find.byKey(const Key('change-origin')));
    await tester.pump();
    // The current origin stays in effect while choosing a new one.
    expect(originOf(tester).origin!.label, 'OUR TAMPINES HUB');
    await type(tester, originField, 'ION Orchard');
    await pick(tester, 'ION ORCHARD');

    expect(find.text('From: ION ORCHARD (chosen manually)'), findsOneWidget);
    expect(originOf(tester).origin!.position, ionOrchard.position);
    expect(find.text('To: VIVOCITY'), findsOneWidget);
    expect(destinationOf(tester).place, vivoCity);
  });

  testWidgets('"Keep this origin" cancels a change', (tester) async {
    await pumpApp(tester, deniedApp());
    await type(tester, originField, 'Tampines Hub');
    await pick(tester, 'OUR TAMPINES HUB');
    final origin = originOf(tester).origin!;

    await tester.tap(find.byKey(const Key('change-origin')));
    await tester.pump();
    expect(find.byKey(originField), findsOneWidget);
    await tester.tap(find.byKey(const Key('keep-origin')));
    await tester.pump();

    expect(find.byKey(originField), findsNothing);
    expect(
      find.text('From: OUR TAMPINES HUB (chosen manually)'),
      findsOneWidget,
    );
    expect(originOf(tester).origin, same(origin));
    expect(originOf(tester).phase, OriginPhase.ready);
  });

  testWidgets('with a manual origin, "Try location again" can switch back to '
      'GPS after location is re-enabled', (tester) async {
    final location = FakeLocationService(access: LocationAccess.denied);
    await pumpApp(
      tester,
      buildTestApp(
        location: location,
        environment: FakeEnvironmentRepository(),
        places: places,
      ),
    );
    await type(tester, originField, 'Tampines Hub');
    await pick(tester, 'OUR TAMPINES HUB');

    // Location stays denied: the failure is reported, the origin kept.
    location.reset();
    await tester.tap(find.byKey(const Key('retry-location')));
    await tester.pump();
    expect(find.text('Finding your location…'), findsOneWidget);
    location.answer(LocationAccess.denied);
    await tester.pump();
    expect(
      find.text(
        '${const LocationPermissionDenied().message} '
        'Your chosen origin is kept.',
      ),
      findsOneWidget,
    );
    expect(originOf(tester).origin!.label, 'OUR TAMPINES HUB');

    // Re-enabled: the fix is offered, and only the chip applies it.
    location.reset();
    await tester.tap(find.byKey(const Key('retry-location')));
    await tester.pump();
    location
      ..grant()
      ..fix(bishan);
    await tester.pump();
    expect(find.byKey(const Key('background-location-failure')), findsNothing);
    expect(originOf(tester).origin!.label, 'OUR TAMPINES HUB');
    await tester.tap(find.byKey(const Key('use-current-location')));
    await tester.pump();
    expect(find.text('From: Current location (from GPS)'), findsOneWidget);
  });

  testWidgets('an unanswered location prompt does not block the app: manual '
      'search appears after the permission timeout', (tester) async {
    final location = FakeLocationService(); // the prompt is never answered
    await pumpApp(
      tester,
      buildTestApp(
        location: location,
        environment: FakeEnvironmentRepository(),
        places: places,
      ),
    );
    expect(find.text('Checking location permission…'), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
    expect(find.text(OriginCard.fallbackPrompt), findsOneWidget);
    expect(
      find.text(const LocationPermissionUnanswered().message),
      findsOneWidget,
    );
    await type(tester, originField, 'Tampines Hub');
    await pick(tester, 'OUR TAMPINES HUB');
    expect(find.text(DestinationCard.prompt), findsOneWidget);
  });

  testWidgets('changing the destination never alters the origin', (
    tester,
  ) async {
    await pumpApp(tester, deniedApp());
    await type(tester, originField, 'Tampines Hub');
    await pick(tester, 'OUR TAMPINES HUB');
    final origin = originOf(tester).origin!;

    await type(tester, destinationField, 'VivoCity');
    await pick(tester, 'VIVOCITY');
    await tester.tap(find.byKey(const Key('change-destination')));
    await tester.pump();
    expect(find.text('To: VIVOCITY'), findsOneWidget); // kept while editing
    await type(tester, destinationField, 'ION Orchard');
    await pick(tester, 'ION ORCHARD');

    expect(find.text('To: ION ORCHARD'), findsOneWidget);
    expect(originOf(tester).origin, same(origin));
  });

  testWidgets('late GPS never overwrites a searched origin; only the chip '
      'switches back, and the destination is untouched', (tester) async {
    final location = FakeLocationService(access: LocationAccess.granted);
    await pumpApp(
      tester,
      buildTestApp(
        location: location,
        environment: FakeEnvironmentRepository(),
        places: places,
      ),
    );
    await tester.pump(const Duration(seconds: 10)); // timeout → manual
    expect(find.text(OriginCard.fallbackPrompt), findsOneWidget);

    await type(tester, originField, 'Tampines Hub');
    location.fix(bishan); // late, while typing: offered, not applied
    await tester.pump();
    expect(originOf(tester).origin, isNull);
    expect(find.byKey(const Key('use-current-location')), findsOneWidget);

    await pick(tester, 'OUR TAMPINES HUB');
    await type(tester, destinationField, 'VivoCity');
    await pick(tester, 'VIVOCITY');
    await tester.pump(const Duration(seconds: 30));
    expect(
      find.text('From: OUR TAMPINES HUB (chosen manually)'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('use-current-location')));
    await tester.pump();
    expect(find.text('From: Current location (from GPS)'), findsOneWidget);
    expect(destinationOf(tester).place, vivoCity);
  });

  testWidgets('search race in the UI: a slow older answer is not shown', (
    tester,
  ) async {
    places.results['viv'] = [ionOrchard];
    places.hold('viv');
    await pumpApp(tester, deniedApp());
    await type(tester, originField, 'viv'); // in flight, held
    await type(tester, originField, 'VivoCity');
    expect(find.text('VIVOCITY'), findsOneWidget);

    places.release('viv');
    await tester.pump();
    expect(find.text('VIVOCITY'), findsOneWidget);
    expect(find.text('ION ORCHARD'), findsNothing);
  });
}
