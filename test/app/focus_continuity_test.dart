// E8 focus continuity (docs/e8-focus-continuity-implementation-plan.md): a
// control that removes or disables itself when pressed hands focus on.
// #80: "Use my current location" → "Change". #81: the manual-origin "Try
// location again" → the origin section's FocusLanding, before it disables.
// Real Tab, Shift+Tab and Enter key events, so focus traversal and the
// highlight mode are Flutter's own.
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/core/errors/app_failure.dart';
import 'package:sg_smart_commute/core/geo/geo.dart';
import 'package:sg_smart_commute/core/location/location_service.dart';
import 'package:sg_smart_commute/core/ui/focus_landing.dart';

import '../../integration_test/fakes/fake_environment_repository.dart';
import '../../integration_test/fakes/fake_location_service.dart';
import '../../integration_test/fakes/fake_place_search_repository.dart';
import '../../integration_test/fakes/test_app.dart';

const bishan = LatLng(1.3508, 103.8485);

Finder key(String k) => find.byKey(Key(k));

final chip = key('use-current-location');
final change = key('change-origin');
final originField = key('manual-origin-field');
final destinationField = key('destination-field');
final retry = key('retry-location');
final busy = find.text('Finding your location…');
final failureNote = key('background-location-failure');

/// Whether the origin section's FocusLanding has the primary focus.
bool onLanding() =>
    FocusManager.instance.primaryFocus?.debugLabel == 'origin-section';

/// Whether the primary focus is [f] or inside it.
bool focusIn(Finder f) {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  final target = f.evaluate().first;
  var inside = identical(context, target);
  context.visitAncestorElements((e) {
    inside = inside || identical(e, target);
    return !inside;
  });
  return inside;
}

/// The primary focus, described for a failure message.
String focusName() {
  final node = FocusManager.instance.primaryFocus;
  final keys = <String>[];
  node?.context?.visitAncestorElements((e) {
    final k = e.widget.key;
    if (k is ValueKey) keys.add('$k');
    return keys.isEmpty;
  });
  return '$node $keys';
}

/// A key press; the second pump runs any post-frame focus move.
Future<void> press(
  WidgetTester tester,
  LogicalKeyboardKey k, {
  bool shift = false,
}) async {
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(k);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pump();
  await tester.pump();
}

/// Moves focus with Tab (or Shift+Tab) until [f] has it.
Future<void> tabTo(WidgetTester tester, Finder f, {bool shift = false}) async {
  for (var i = 0; i < 40; i++) {
    if (focusIn(f)) return;
    await press(tester, LogicalKeyboardKey.tab, shift: shift);
  }
  fail('${shift ? 'Shift+Tab' : 'Tab'} never reached $f');
}

/// Two frames: a provider change that lands after a frame has begun shows in
/// the next one.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

Future<void> pumpTall(WidgetTester tester, Widget app) async {
  tester.view.physicalSize = const Size(1080, 5000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
  await tester.pump();
}

/// Location granted but no fix: after the 10 s timeout the fallback prompt
/// asks for a place. Returns the service, so a test can send the late fix.
Future<FakeLocationService> fallback(WidgetTester tester) async {
  final location = FakeLocationService(access: LocationAccess.granted);
  await pumpTall(
    tester,
    buildTestApp(
      location: location,
      environment: FakeEnvironmentRepository(),
      places: FakePlaceSearchRepository(),
    ),
  );
  await tester.pump(const Duration(seconds: 10));
  return location;
}

Future<void> typeOrigin(WidgetTester tester) async {
  await tester.enterText(originField, 'Tampines Hub');
  await tester.pump(pastSearchDebounce);
  await tester.pump();
}

/// A manual origin, then a late fix: the chip is offered in the normal view.
Future<void> offerChip(WidgetTester tester) async {
  final location = await fallback(tester);
  await typeOrigin(tester);
  await tester.tap(find.text('OUR TAMPINES HUB'));
  await tester.pump();
  await tester.pump(); // "Change" focused after the pick
  location.fix(bishan); // late: only offered
  await settle(tester);
  expect(chip, findsOneWidget);
}

/// After the chip: the GPS origin, focus on "Change", and one Tab on to the
/// destination field (D1).
Future<void> expectOnChangeThenDestination(WidgetTester tester) async {
  expect(find.text('From: Current location'), findsOneWidget);
  expect(chip, findsNothing);
  expect(focusIn(change), isTrue, reason: 'focus on ${focusName()}');
  await press(tester, LogicalKeyboardKey.tab);
  expect(focusIn(destinationField), isTrue, reason: 'Tab: ${focusName()}');
}

void main() {
  group('#80: "Use my current location" hands focus to "Change"', () {
    testWidgets('T80-1 normal view, reached by Tab', (tester) async {
      await offerChip(tester);
      await tabTo(tester, chip);
      await press(tester, LogicalKeyboardKey.enter);
      await expectOnChangeThenDestination(tester);
    });

    testWidgets('T80-2 normal view, reached by Shift+Tab from the '
        'destination field', (tester) async {
      await offerChip(tester);
      await tabTo(tester, destinationField);
      await tabTo(tester, chip, shift: true);
      await press(tester, LogicalKeyboardKey.enter);
      await expectOnChangeThenDestination(tester);
    });

    testWidgets('T80-3 with "Change" open: the chip under the search field', (
      tester,
    ) async {
      await offerChip(tester);
      await tester.tap(change);
      await tester.pump();
      expect(focusIn(originField), isTrue);
      await tabTo(tester, chip);
      await press(tester, LogicalKeyboardKey.enter);
      expect(
        FocusManager.instance.primaryFocus,
        isNot(isA<FocusScopeNode>()),
        reason: 'not dropped to the route',
      );
      await expectOnChangeThenDestination(tester);
    });

    testWidgets('T80-4 the launch fallback while typing: a late fix is '
        'offered under the field', (tester) async {
      final location = await fallback(tester);
      await typeOrigin(tester);
      location.fix(bishan);
      await settle(tester);
      expect(chip, findsOneWidget);
      await tabTo(tester, chip);
      await press(tester, LogicalKeyboardKey.enter);
      await expectOnChangeThenDestination(tester);
    });

    testWidgets('T80-5 touch: a tap leaves "Change" focused, with no ring', (
      tester,
    ) async {
      await offerChip(tester);
      await tester.tap(chip);
      await tester.pump();
      await tester.pump();
      expect(FocusManager.instance.highlightMode, FocusHighlightMode.touch);
      expect(focusIn(change), isTrue, reason: 'focus on ${focusName()}');
      final material = tester.widget<Material>(
        find.descendant(of: change, matching: find.byType(Material)).first,
      );
      expect(
        (material.shape! as OutlinedBorder).side,
        BorderSide.none,
        reason: 'touch mode: the stock look, no ring (E7 D1)',
      );
    });

    testWidgets('T80-6 semantics: the chip is still announced, the new '
        'origin line is not, and the focus flag is on "Change"', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        await offerChip(tester);
        expect(
          tester.getSemantics(chip),
          isSemantics(
            isLiveRegion: true,
            isButton: true,
            label: 'Use my current location',
          ),
        );
        await tabTo(tester, chip);
        await press(tester, LogicalKeyboardKey.enter);
        expect(
          tester.getSemantics(key('origin-line')),
          isNot(isSemantics(isLiveRegion: true)),
        );
        expect(
          tester.getSemantics(change),
          isSemantics(isFocused: true, label: 'Change origin'),
        );
      } finally {
        semantics.dispose();
      }
    });
  });

  group('#81: the manual-origin "Try location again" hands focus to the '
      'origin section', () {
    /// Location denied at launch, then a searched origin: "Change" has focus
    /// and "Try location again" is offered. The next attempt waits for the
    /// test to answer it.
    Future<FakeLocationService> manualOrigin(WidgetTester tester) async {
      final location = FakeLocationService(access: LocationAccess.denied);
      await pumpTall(
        tester,
        buildTestApp(
          location: location,
          environment: FakeEnvironmentRepository(),
          places: FakePlaceSearchRepository(),
        ),
      );
      await typeOrigin(tester);
      await tester.tap(find.text('OUR TAMPINES HUB'));
      await settle(tester);
      expect(focusIn(change), isTrue);
      location.reset();
      return location;
    }

    /// Tab to the button and press Enter: the attempt runs.
    Future<void> retryByTab(WidgetTester tester) async {
      await tabTo(tester, retry);
      await press(tester, LogicalKeyboardKey.enter);
      expect(busy, findsOneWidget);
    }

    void expectOnLanding([String when = '']) {
      expect(onLanding(), isTrue, reason: '$when focus on ${focusName()}');
    }

    testWidgets('T81-1 reached by Tab: on the landing while busy; Tab moves '
        'on to "Change"', (tester) async {
      await manualOrigin(tester);
      await retryByTab(tester);
      expectOnLanding();
      expect(FocusManager.instance.primaryFocus, isNot(isA<FocusScopeNode>()));
      await press(tester, LogicalKeyboardKey.tab);
      expect(focusIn(change), isTrue, reason: 'Tab: ${focusName()}');
    });

    testWidgets('T81-1 reached by Tab: Shift+Tab from the landing moves to '
        'the control before the route card', (tester) async {
      await manualOrigin(tester);
      await retryByTab(tester);
      expectOnLanding();
      await press(tester, LogicalKeyboardKey.tab, shift: true);
      expect(
        focusIn(key('palette-button')),
        isTrue,
        reason: 'Shift+Tab: ${focusName()}',
      );
    });

    testWidgets('T81-2 reached by Shift+Tab from the destination field: on '
        'the landing, not in the field, no keyboard', (tester) async {
      await manualOrigin(tester);
      await tabTo(tester, destinationField);
      await tabTo(tester, retry, shift: true);
      await press(tester, LogicalKeyboardKey.enter);
      expect(busy, findsOneWidget);
      expectOnLanding();
      expect(focusIn(destinationField), isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
      await press(tester, LogicalKeyboardKey.tab);
      expect(focusIn(change), isTrue, reason: 'Tab: ${focusName()}');
    });

    group('T81-3 focus stays on the landing after the outcome', () {
      testWidgets('success: the chip is offered and announced', (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          final location = await manualOrigin(tester);
          await retryByTab(tester);
          location
            ..grant()
            ..fix(bishan);
          await settle(tester);
          expect(busy, findsNothing);
          expect(
            tester.getSemantics(chip),
            isSemantics(
              isLiveRegion: true,
              isButton: true,
              label: 'Use my current location',
            ),
          );
          expectOnLanding('after the fix:');
        } finally {
          semantics.dispose();
        }
      });

      /// The #57 note, announced, and focus still on the landing.
      void expectFailureNote(WidgetTester tester, LocationFailure reason) {
        expect(busy, findsNothing);
        expect(
          tester.getSemantics(failureNote),
          isSemantics(
            isLiveRegion: true,
            label: '${reason.message} Your chosen origin is kept.',
          ),
        );
        expectOnLanding('after $reason:');
      }

      testWidgets('failure: denied', (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          final location = await manualOrigin(tester);
          await retryByTab(tester);
          location.answer(LocationAccess.denied);
          await settle(tester);
          expectFailureNote(tester, const LocationPermissionDenied());
        } finally {
          semantics.dispose();
        }
      });

      testWidgets('timeout: the permission prompt is not answered', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        try {
          await manualOrigin(tester);
          await retryByTab(tester);
          await tester.pump(const Duration(seconds: 10));
          await settle(tester);
          expectFailureNote(tester, const LocationPermissionUnanswered());
        } finally {
          semantics.dispose();
        }
      });

      testWidgets('timeout: granted, but no fix', (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          final location = await manualOrigin(tester);
          await retryByTab(tester);
          location.grant();
          await settle(tester);
          await tester.pump(const Duration(seconds: 10));
          await settle(tester);
          expectFailureNote(tester, const LocationTimeout());
        } finally {
          semantics.dispose();
        }
      });
    });

    testWidgets('T81-4 touch: a tap leaves the landing focused, with no ring', (
      tester,
    ) async {
      await manualOrigin(tester);
      await tester.tap(retry);
      await settle(tester);
      expect(FocusManager.instance.highlightMode, FocusHighlightMode.touch);
      expectOnLanding();
      final ring = find.ancestor(of: busy, matching: find.byType(FocusRing));
      final box = tester.widget<DecoratedBox>(
        find.descendant(of: ring.first, matching: find.byType(DecoratedBox)),
      );
      expect(
        (box.decoration as BoxDecoration).border,
        isNull,
        reason: 'touch mode: no ring (E7 D1)',
      );
    });

    testWidgets('T81-5 semantics: the button is still disabled while busy, '
        'and one existing node carries the focus flag', (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await manualOrigin(tester);
        await retryByTab(tester);
        expect(
          tester.getSemantics(retry),
          isSemantics(
            isButton: true,
            hasEnabledState: true,
            isEnabled: false,
            label: 'Try location again',
          ),
        );
        final focused = find.semantics
            .byPredicate(
              (node) =>
                  node.getSemanticsData().flagsCollection.isFocused ==
                  Tristate.isTrue,
            )
            .evaluate()
            .toList();
        expect(focused, hasLength(1), reason: 'one focused node');
        expect(
          focused.single.getSemanticsData().label,
          contains('From: OUR TAMPINES HUB'),
          reason: "the route card's own node, not a new one",
        );
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('T81-6 a fix from this attempt is only offered: after the '
        'chip, the origin line is not announced', (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final location = await manualOrigin(tester);
        await retryByTab(tester);
        location
          ..grant()
          ..fix(bishan);
        await settle(tester);
        await tester.tap(chip);
        await settle(tester);
        expect(find.text('From: Current location'), findsOneWidget);
        expect(
          tester.getSemantics(key('origin-line')),
          isNot(isSemantics(isLiveRegion: true)),
        );
      } finally {
        semantics.dispose();
      }
    });

    // O1 (plan §3.3): the permission prompt is answered after its 10 s bound,
    // so the attempt runs again and disables the re-enabled button without a
    // press. Focus must stay in the origin section, with no text input shown.
    // Focus that is not on the button is left where it is.
    group('T81-7 the button disabled again by a late permission answer', () {
      /// The attempt's permission bound passes: the note shows and the button
      /// is enabled again.
      Future<FakeLocationService> unanswered(WidgetTester tester) async {
        final location = await manualOrigin(tester);
        await retryByTab(tester);
        await tester.pump(const Duration(seconds: 10));
        await settle(tester);
        expect(failureNote, findsOneWidget);
        return location;
      }

      Future<void> answerLate(
        WidgetTester tester,
        FakeLocationService location,
      ) async {
        expect(focusIn(retry), isTrue, reason: 'on the button: ${focusName()}');
        final field = tester
            .widget<EditableText>(
              find.descendant(
                of: destinationField,
                matching: find.byType(EditableText),
              ),
            )
            .focusNode;
        var fieldFocused = false;
        void watch() => fieldFocused = fieldFocused || field.hasFocus;
        field.addListener(watch);
        addTearDown(() => field.removeListener(watch));
        location.grant();
        await settle(tester);
        expect(busy, findsOneWidget, reason: 'the attempt runs again');
        expect(
          tester.widget<TextButton>(retry).onPressed,
          isNull,
          reason: 'still disabled while busy',
        );
        expectOnLanding('after the late answer:');
        expect(fieldFocused, isFalse, reason: 'never in the destination field');
        expect(tester.testTextInput.isVisible, isFalse);
        await press(tester, LogicalKeyboardKey.tab);
        expect(focusIn(change), isTrue, reason: 'Tab: ${focusName()}');
      }

      testWidgets('reached by Tab from the landing', (tester) async {
        final location = await unanswered(tester);
        await tabTo(tester, retry);
        await answerLate(tester, location);
      });

      testWidgets('reached by Shift+Tab from the destination field', (
        tester,
      ) async {
        final location = await unanswered(tester);
        await tabTo(tester, destinationField);
        await tabTo(tester, retry, shift: true);
        await answerLate(tester, location);
      });

      testWidgets('focus elsewhere is left where it is', (tester) async {
        final location = await unanswered(tester);
        await tabTo(tester, destinationField);
        location.grant();
        await settle(tester);
        expect(busy, findsOneWidget);
        expect(
          focusIn(destinationField),
          isTrue,
          reason: 'the user moved on: ${focusName()}',
        );
      });

      testWidgets('touch: the button never had focus, so nothing moves', (
        tester,
      ) async {
        final location = await manualOrigin(tester);
        await tester.tap(retry);
        await settle(tester);
        await tester.pump(const Duration(seconds: 10));
        await settle(tester);
        expect(failureNote, findsOneWidget);
        final before = FocusManager.instance.primaryFocus;
        location.grant();
        await settle(tester);
        expect(busy, findsOneWidget);
        expect(FocusManager.instance.highlightMode, FocusHighlightMode.touch);
        expect(FocusManager.instance.primaryFocus, same(before));
      });
    });
  });
}
