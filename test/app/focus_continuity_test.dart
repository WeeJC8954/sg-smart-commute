// E8 focus continuity (docs/e8-focus-continuity-implementation-plan.md): a
// control that removes or disables itself when pressed hands focus on.
// #80: "Use my current location" → "Change". Real Tab, Shift+Tab and Enter key
// events, so focus traversal and the highlight mode are Flutter's own.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/core/geo/geo.dart';
import 'package:sg_smart_commute/core/location/location_service.dart';

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
}
