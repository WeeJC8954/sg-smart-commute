// Screen-reader and keyboard behaviour of the home screen (guide v2.1 §16,
// accessibility): headings, button labels, live regions and focus.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/core/errors/app_failure.dart';
import 'package:sg_smart_commute/core/geo/geo.dart';
import 'package:sg_smart_commute/core/location/location_service.dart';
import 'package:sg_smart_commute/features/destination/presentation/destination_card.dart';
import 'package:sg_smart_commute/features/origin/presentation/origin_card.dart';

import '../../integration_test/fakes/fake_environment_repository.dart';
import '../../integration_test/fakes/fake_location_service.dart';
import '../../integration_test/fakes/fake_place_search_repository.dart';
import '../../integration_test/fakes/test_app.dart';

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

/// Taps a result; the second pump runs the post-frame focus move.
Future<void> pick(WidgetTester tester, String result) async {
  await tester.tap(find.text(result));
  await tester.pump();
  await tester.pump();
}

bool fieldFocused(WidgetTester tester, Key field) => tester
    .widget<EditableText>(
      find.descendant(
        of: find.byKey(field),
        matching: find.byType(EditableText),
      ),
    )
    .focusNode
    .hasFocus;

bool buttonFocused(WidgetTester tester, String key) =>
    tester.widget<TextButton>(find.byKey(Key(key))).focusNode!.hasFocus;

void main() {
  late FakePlaceSearchRepository places;
  late FakeEnvironmentRepository env;

  setUp(() {
    places = FakePlaceSearchRepository();
    env = FakeEnvironmentRepository();
  });

  Widget deniedApp() => buildTestApp(
    location: FakeLocationService(access: LocationAccess.denied),
    environment: env,
    places: places,
  );

  Widget gpsApp() => buildTestApp(
    location: FakeLocationService(
      access: LocationAccess.granted,
      position: bishan,
    ),
    environment: env,
    places: places,
  );

  testWidgets('section titles are headings for screen-reader navigation', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpApp(tester, deniedApp());

    expect(
      tester.getSemantics(find.text('Conditions')),
      isSemantics(isHeader: true, label: 'Conditions'),
    );
    expect(
      tester.getSemantics(find.text(OriginCard.fallbackPrompt)),
      isSemantics(isHeader: true),
    );
    // Only the title: the failure text under it is not a heading.
    expect(
      tester.getSemantics(find.text('Location permission was not granted.')),
      isNot(isSemantics(isHeader: true)),
    );

    await type(tester, originField, 'Tampines Hub');
    await pick(tester, 'OUR TAMPINES HUB');
    expect(
      tester.getSemantics(find.text(DestinationCard.prompt)),
      isSemantics(isHeader: true),
    );
    semantics.dispose();
  });

  testWidgets('each "Change" says what it changes', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpApp(tester, gpsApp());
    await tester.pump();
    await type(tester, destinationField, 'VivoCity');
    await pick(tester, 'VIVOCITY');

    expect(find.bySemanticsLabel('Change origin'), findsOneWidget);
    expect(find.bySemanticsLabel('Change destination'), findsOneWidget);
    // The visible text is unchanged.
    expect(find.text('Change'), findsNWidgets(2));
    semantics.dispose();
  });

  testWidgets('each Retry names what it retries', (tester) async {
    final semantics = tester.ensureSemantics();
    env
      ..failForecast = const NetworkUnavailable()
      ..failPsi = const NetworkUnavailable();
    places.failures['vivocity'] = const NetworkUnavailable();
    await pumpApp(tester, gpsApp());
    await tester.pump();

    expect(find.bySemanticsLabel('Retry 2-hr forecast'), findsOneWidget);
    expect(find.bySemanticsLabel('Retry 24-hr PSI'), findsOneWidget);
    await type(tester, destinationField, 'VivoCity');
    expect(find.bySemanticsLabel('Retry place search'), findsOneWidget);
    expect(find.text('Retry'), findsNWidgets(3));
    semantics.dispose();
  });

  testWidgets('place-search status changes are announced (live regions)', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    places.failures['vivocity'] = const NetworkUnavailable();
    await pumpApp(tester, deniedApp());

    await type(tester, originField, 'zz');
    expect(
      tester.getSemantics(
        find.text('Type at least 3 characters, or a 6-digit postal code.'),
      ),
      isSemantics(isLiveRegion: true),
    );

    await type(tester, originField, 'Nowhere Lane');
    expect(
      tester.getSemantics(find.textContaining('No places found for')),
      isSemantics(isLiveRegion: true),
    );

    await type(tester, originField, '098585');
    expect(
      tester.getSemantics(find.text('1 match. Tap it to confirm.')),
      isSemantics(isLiveRegion: true),
    );
    // The results themselves are not announced as they appear.
    expect(
      tester.getSemantics(find.text('VIVOCITY')),
      isNot(isSemantics(isLiveRegion: true)),
    );

    await type(tester, originField, 'VivoCity');
    expect(
      tester.getSemantics(find.text(const NetworkUnavailable().message)),
      isSemantics(isLiveRegion: true),
    );
    semantics.dispose();
  });

  testWidgets('focus follows Change, select and Keep', (tester) async {
    await pumpApp(tester, deniedApp());
    // The launch fallback prompt doesn't take focus (no keyboard unasked).
    expect(fieldFocused(tester, originField), isFalse);

    await type(tester, originField, 'Tampines Hub');
    await pick(tester, 'OUR TAMPINES HUB');
    expect(buttonFocused(tester, 'change-origin'), isTrue);
    // The destination prompt appears unfocused too.
    expect(fieldFocused(tester, destinationField), isFalse);

    await tester.tap(find.byKey(const Key('change-origin')));
    await tester.pump();
    expect(fieldFocused(tester, originField), isTrue);

    await tester.tap(find.byKey(const Key('keep-origin')));
    await tester.pump();
    await tester.pump();
    expect(buttonFocused(tester, 'change-origin'), isTrue);

    await type(tester, destinationField, 'VivoCity');
    await pick(tester, 'VIVOCITY');
    expect(buttonFocused(tester, 'change-destination'), isTrue);

    await tester.tap(find.byKey(const Key('change-destination')));
    await tester.pump();
    expect(fieldFocused(tester, destinationField), isTrue);

    await tester.tap(find.text('Keep this destination'));
    await tester.pump();
    await tester.pump();
    expect(buttonFocused(tester, 'change-destination'), isTrue);
  });
}
