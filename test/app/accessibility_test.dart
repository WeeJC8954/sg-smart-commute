// Screen-reader and keyboard behaviour of the home screen (guide v2.1 §16,
// accessibility): headings, button labels, live regions and focus.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  await tester.pump(pastSearchDebounce);
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

/// The nearest [Focus] above [finder]'s widget has the primary focus.
bool focusedAt(WidgetTester tester, Finder finder) =>
    Focus.maybeOf(
      tester.element(finder),
      createDependency: false,
    )?.hasPrimaryFocus ??
    false;

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

  testWidgets('a tile Retry that removes itself leaves focus on the tile '
      'title, which Tab does not stop at (#56)', (tester) async {
    final semantics = tester.ensureSemantics();
    env.failPm25 = const NetworkUnavailable();
    await pumpApp(tester, gpsApp());
    await tester.pump();
    final title = find.descendant(
      of: find.byKey(const Key('tile-pm25')),
      matching: find.text('1-hr PM2.5'),
    );
    expect(focusedAt(tester, title), isFalse);

    env.failPm25 = null;
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('tile-pm25')),
        matching: find.text('Retry'),
      ),
    );
    await tester.pump();
    expect(focusedAt(tester, title), isTrue);
    expect(tester.getSemantics(title), isSemantics(isFocused: true));
    await tester.pump();
    expect(find.textContaining('µg/m³'), findsOneWidget);
    expect(focusedAt(tester, title), isTrue, reason: 'kept once it loads');

    // Never a Tab stop of its own: Tab moves on and does not come back.
    for (var i = 0; i < 30; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(focusedAt(tester, title), isFalse);
    }
    semantics.dispose();
  });

  testWidgets('the result of "Try location again" is announced (#57)', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final location = FakeLocationService(access: LocationAccess.denied);
    await pumpApp(
      tester,
      buildTestApp(location: location, environment: env, places: places),
    );
    await type(tester, originField, 'Tampines Hub');
    await pick(tester, 'OUR TAMPINES HUB');

    location.reset();
    await tester.tap(find.byKey(const Key('retry-location')));
    await tester.pump();
    location.answer(LocationAccess.denied);
    await tester.pump();
    expect(
      tester.getSemantics(find.byKey(const Key('background-location-failure'))),
      isSemantics(
        isLiveRegion: true,
        label:
            '${const LocationPermissionDenied().message} '
            'Your chosen origin is kept.',
      ),
    );

    location.reset();
    await tester.tap(find.byKey(const Key('retry-location')));
    await tester.pump();
    location
      ..grant()
      ..fix(bishan);
    await tester.pump();
    expect(
      tester.getSemantics(find.byKey(const Key('use-current-location'))),
      isSemantics(
        isLiveRegion: true,
        isButton: true,
        label: 'Use my current location',
      ),
    );
    semantics.dispose();
  });

  testWidgets('the fallback prompt\'s "Try location again" keeps focus in '
      'the origin section, and the failure it brings back is a live region '
      '(#65)', (tester) async {
    final semantics = tester.ensureSemantics();
    final location = FakeLocationService(access: LocationAccess.denied);
    await pumpApp(
      tester,
      buildTestApp(location: location, environment: env, places: places),
    );
    final retry = find.text('Try location again');
    // A keyboard or screen-reader user is on the button.
    Focus.of(tester.element(retry)).requestFocus();
    await tester.pump();

    location.reset();
    await tester.tap(retry);
    await tester.pump();
    // The button turned into a spinner: focus is on the section around it,
    // not dropped back to the page.
    final busy = find.text('Checking location permission…');
    expect(busy, findsOneWidget);
    expect(focusedAt(tester, busy), isTrue);
    expect(FocusManager.instance.primaryFocus, isNot(isA<FocusScopeNode>()));

    location.answer(LocationAccess.denied);
    await tester.pump();
    expect(focusedAt(tester, find.text(OriginCard.fallbackPrompt)), isTrue);
    expect(
      tester.getSemantics(find.text('Location permission was not granted.')),
      isSemantics(
        isLiveRegion: true,
        label: 'Location permission was not granted.',
      ),
    );
    semantics.dispose();
  });

  // The fallback prompt's "Try location again" and the fix it gets (#65).
  // Its 10 s timeout falls back to manual entry, but the attempt goes on.
  group('a fix after the fallback "Try location again"', () {
    Future<FakeLocationService> fallback(WidgetTester tester) async {
      final location = FakeLocationService(access: LocationAccess.denied);
      await pumpApp(
        tester,
        buildTestApp(location: location, environment: env, places: places),
      );
      return location;
    }

    /// Presses "Try location again"; permission is granted, and no fix
    /// arrives within the timeout.
    Future<void> retryAndTimeOut(
      WidgetTester tester,
      FakeLocationService location,
    ) async {
      location.reset();
      await tester.tap(find.text('Try location again'));
      await tester.pump();
      location.grant();
      await tester.pump();
      await tester.pump(const Duration(seconds: 10));
      expect(find.text('Finding your location took too long.'), findsOneWidget);
    }

    testWidgets('a late fix, after the timeout, is announced, and only once', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final location = await fallback(tester);
      await retryAndTimeOut(tester, location);

      location.fix(bishan);
      await tester.pump();
      expect(
        tester.getSemantics(find.text('From: Current location')),
        isSemantics(isLiveRegion: true, label: 'From: Current location'),
      );

      // The same line built again later is not announced again.
      await tester.tap(find.byKey(const Key('change-origin')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('keep-origin')));
      await tester.pump();
      await tester.pump();
      expect(
        tester.getSemantics(find.text('From: Current location')),
        isNot(isSemantics(isLiveRegion: true)),
      );
      semantics.dispose();
    });

    testWidgets('a late fix never replaces a place the user is entering; it '
        'is only offered', (tester) async {
      final semantics = tester.ensureSemantics();
      final location = await fallback(tester);
      await retryAndTimeOut(tester, location);

      await type(tester, originField, 'Tampines Hub');
      location.fix(bishan);
      await tester.pump();
      expect(find.text('From: Current location'), findsNothing);
      expect(find.byKey(const Key('use-current-location')), findsOneWidget);

      await pick(tester, 'OUR TAMPINES HUB');
      expect(
        tester.getSemantics(find.text('From: OUR TAMPINES HUB')),
        isNot(isSemantics(isLiveRegion: true)),
      );
      semantics.dispose();
    });

    testWidgets('a superseded attempt\'s late fix is dropped and announces '
        'nothing; the current attempt\'s fix is announced', (tester) async {
      final semantics = tester.ensureSemantics();
      final location = await fallback(tester);
      await retryAndTimeOut(tester, location); // attempt 1

      location.reset(); // attempt 2
      await tester.tap(find.text('Try location again'));
      await tester.pump();
      location.fixAttempt(1, bishan);
      await tester.pump();
      expect(find.text('From: Current location'), findsNothing);

      location
        ..grant()
        ..fix(bishan);
      await tester.pump();
      expect(
        tester.getSemantics(find.text('From: Current location')),
        isSemantics(isLiveRegion: true, label: 'From: Current location'),
      );
      semantics.dispose();
    });
  });

  testWidgets('a failed refresh is announced (#57)', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpApp(tester, gpsApp());
    await tester.pump();
    await tester.pump();
    env.failPsi = const NetworkUnavailable();
    await tester.tap(find.byKey(const Key('refresh-conditions')));
    await tester.pump();
    await tester.pump();
    expect(
      tester.getSemantics(
        find.text("Couldn't refresh: ${const NetworkUnavailable().message}"),
      ),
      isSemantics(isLiveRegion: true),
    );
    semantics.dispose();
  });
}
