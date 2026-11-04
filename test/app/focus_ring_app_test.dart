// E7 T2 (app part), T3, T4, T6–T8: the keyboard focus ring in the real app.
// Keyboard focus shows a 2 px primary ring on every focusable control; touch
// keeps today's look; a mouse keeps the highlight mode it finds (Flutter
// 3.47.2), so a code-driven focus move after a click shows the ring only in
// traditional mode; hover alone never shows it (D1, D3, D4).
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/app/home_screen.dart';
import 'package:sg_smart_commute/core/geo/geo.dart';
import 'package:sg_smart_commute/core/location/location_service.dart';
import 'package:sg_smart_commute/core/ui/focus_landing.dart';
import 'package:sg_smart_commute/core/ui/focus_ring_theme.dart';
import 'package:sg_smart_commute/features/appearance/domain/app_palette.dart';
import 'package:sg_smart_commute/features/appearance/presentation/palette_theme.dart';

import '../../integration_test/fakes/fake_bus_arrival_repository.dart';
import '../../integration_test/fakes/fake_bus_network.dart';
import '../../integration_test/fakes/fake_environment_repository.dart';
import '../../integration_test/fakes/fake_location_service.dart';
import '../../integration_test/fakes/fake_map.dart';
import '../../integration_test/fakes/fake_palette_store.dart';
import '../../integration_test/fakes/fake_place_search_repository.dart';
import '../../integration_test/fakes/fake_route_geometry.dart';
import '../../integration_test/fakes/test_app.dart';

const bishan = LatLng(1.3508, 103.8485);

const desktop = TargetPlatformVariant({TargetPlatform.windows});

/// The approved width (plan §2), written out so a change to the constant fails.
const ringWidth = 2.0;

Finder key(String k) => find.byKey(Key(k));

/// The side a button, menu item or chip paints: its Material's border.
BorderSide paintedSide(WidgetTester tester, Finder control) {
  final material = tester.widget<Material>(
    find.descendant(of: control, matching: find.byType(Material)).first,
  );
  return (material.shape! as OutlinedBorder).side;
}

Color primaryAt(WidgetTester tester, Finder f) =>
    Theme.of(tester.element(f.first)).colorScheme.primary;

BorderSide ringAt(WidgetTester tester, Finder f) =>
    BorderSide(color: primaryAt(tester, f), width: ringWidth);

/// The border drawn by the [FocusRing] of [target]: the first one inside it,
/// else the nearest one around it. Null while no ring shows.
Border? ringBorder(WidgetTester tester, Finder target) {
  final inside = find.descendant(of: target, matching: find.byType(FocusRing));
  final ring = inside.evaluate().isNotEmpty
      ? inside.first
      : find.ancestor(of: target, matching: find.byType(FocusRing)).first;
  final box = tester.widget<DecoratedBox>(
    find.descendant(of: ring, matching: find.byType(DecoratedBox)).first,
  );
  return (box.decoration as BoxDecoration).border as Border?;
}

Border ringBox(WidgetTester tester, Finder f) =>
    Border.all(color: primaryAt(tester, f), width: ringWidth);

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

Future<void> press(WidgetTester tester, LogicalKeyboardKey k) async {
  await tester.sendKeyEvent(k);
  await tester.pump();
  await tester.pump();
}

/// Tabs forward until [f] has focus (a real keyboard path).
Future<void> tabTo(WidgetTester tester, Finder f) async {
  for (var i = 0; i < 80; i++) {
    if (focusIn(f)) return;
    await press(tester, LogicalKeyboardKey.tab);
  }
  fail('Tab never reached $f');
}

/// A touch on an empty part of the page.
Future<void> touchEmpty(WidgetTester tester) async {
  await tester.tapAt(const Offset(1075, 4995));
  await tester.pump();
}

Future<void> tapVisible(
  WidgetTester tester,
  Finder f, {
  PointerDeviceKind kind = PointerDeviceKind.touch,
}) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f, kind: kind);
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

/// Bishan by GPS → VivoCity: two or more bus options, the map closed. The
/// result is picked with [kind] (a mouse leaves the highlight mode as is).
Future<void> journey(
  WidgetTester tester, {
  PointerDeviceKind kind = PointerDeviceKind.touch,
  Future<void> Function(Finder)? pick,
}) async {
  await pumpTall(
    tester,
    buildTestApp(
      location: FakeLocationService(
        access: LocationAccess.granted,
        position: bishan,
      ),
      environment: FakeEnvironmentRepository(),
      places: FakePlaceSearchRepository(),
      busNetwork: FakeBusNetworkRepository(),
      busArrivals: FakeBusArrivalRepository(),
      routeGeometry: FakeRouteGeometryRepository(),
      mapTiles: FakeTileProvider.new,
      paletteStore: FakePaletteStore(),
    ),
  );
  await tester.enterText(key('destination-field'), 'VivoCity');
  await tester.pump(pastSearchDebounce);
  await tester.pump();
  if (pick != null) {
    await pick(find.text('VIVOCITY'));
  } else {
    await tester.tap(find.text('VIVOCITY'), kind: kind);
  }
  await tester.pump();
  await tester.pump();
  expect(key('select-option-F10'), findsOneWidget);
}

Future<void> boot(WidgetTester tester) => pumpTall(
  tester,
  buildTestApp(
    location: FakeLocationService(access: LocationAccess.denied),
    environment: FakeEnvironmentRepository(),
    places: FakePlaceSearchRepository(),
    paletteStore: FakePaletteStore(),
  ),
);

void main() {
  group('T2: the theme', () {
    testWidgets('touch mode: the app theme is the E1 palette theme itself; '
        'keyboard: the same with focus rings', (tester) async {
      await boot(tester);
      final light = paletteTheme(AppPalette.teal, Brightness.light);
      final ring = BorderSide(color: light.colorScheme.primary, width: 2);
      ThemeData app() => Theme.of(tester.element(find.byType(HomeScreen)));
      void expectRings({required bool on}) {
        final t = app();
        expect(t.colorScheme, light.colorScheme);
        for (final style in [
          t.textButtonTheme.style,
          t.iconButtonTheme.style,
          t.outlinedButtonTheme.style,
          t.menuButtonTheme.style,
        ]) {
          expect(style?.side?.resolve({WidgetState.focused}), on ? ring : null);
          expect(style?.side?.resolve({WidgetState.hovered}), isNull);
        }
        expect(t.chipTheme, light.chipTheme, reason: 'chips: FocusRingWithin');
      }

      await touchEmpty(tester);
      expectRings(on: false);
      expect(app().textButtonTheme, light.textButtonTheme);
      expect(app().chipTheme, light.chipTheme);
      await press(tester, LogicalKeyboardKey.shiftLeft);
      expectRings(on: true);
      await touchEmpty(tester);
      expectRings(on: false);
    });
  });

  group('T3: keyboard focus shows the ring on every control type', () {
    testWidgets('app bar and page IconButtons: About, palette, Refresh '
        'conditions', (tester) async {
      await boot(tester);
      for (final k in [
        'about-button',
        'palette-button',
        'refresh-conditions',
      ]) {
        await tabTo(tester, key(k));
        expect(paintedSide(tester, key(k)), ringAt(tester, key(k)), reason: k);
      }
      expect(
        paintedSide(tester, key('about-button')),
        BorderSide.none,
        reason: 'unfocused again: stock',
      );
    });

    testWidgets('TextButton, OutlinedButton (2 px, not the stock 1 px: D3), '
        'TextButton.icon and the arrivals refresh', (tester) async {
      await journey(tester);
      for (final k in [
        'change-origin',
        'change-destination',
        'arrivals-refresh',
        'select-option-F10',
        'show-map',
      ]) {
        await tabTo(tester, key(k).first);
        expect(
          paintedSide(tester, key(k).first),
          ringAt(tester, key(k)),
          reason: k,
        );
      }
    });

    testWidgets('code-driven focus in keyboard mode: Enter on Show map moves '
        'focus to Hide map, which shows the ring; the attribution links and '
        'the two-colour map ring (D2)', (tester) async {
      await journey(tester);
      await tabTo(tester, key('show-map'));
      await press(tester, LogicalKeyboardKey.enter);
      expect(focusIn(key('hide-map')), isTrue);
      expect(
        paintedSide(tester, key('hide-map')),
        ringAt(tester, key('hide-map')),
      );

      await tabTo(tester, find.byType(FlutterMap));
      final map = find.byType(FlutterMap);
      final scheme = Theme.of(tester.element(map)).colorScheme;
      final ring = find.ancestor(of: map, matching: find.byType(FocusRing));
      final boxes = tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: ring.first,
              matching: find.byType(DecoratedBox),
            ),
          )
          .take(2)
          .map((b) => (b.decoration as BoxDecoration).border)
          .toList();
      expect(boxes[0], Border.all(color: focusRingColor(scheme), width: 2));
      expect(
        boxes[1],
        Border.all(color: focusRingBandColor(scheme), width: 4),
        reason: 'a 2 px surface band shows inside the 2 px ring',
      );

      for (final k in ['attribution-onemap', 'attribution-sla']) {
        final link = find.descendant(
          of: key(k),
          matching: find.byType(InkWell),
        );
        await tabTo(tester, link);
        expect(ringBorder(tester, link), ringBox(tester, link), reason: k);
      }
    });

    testWidgets('search: Clear (IconButton) and each result (ListTile); the '
        'TextField keeps its own stock focused border', (tester) async {
      await journey(tester);
      await tabTo(tester, key('change-destination'));
      await press(tester, LogicalKeyboardKey.enter);
      await tester.enterText(key('destination-field'), 'VivoCity');
      await tester.pump(pastSearchDebounce);
      await tester.pump();
      final clear = find.descendant(
        of: key('destination-field'),
        matching: find.byType(IconButton),
      );
      await tabTo(tester, clear);
      expect(paintedSide(tester, clear), ringAt(tester, clear));
      final result = find.ancestor(
        of: find.text('VIVOCITY'),
        matching: find.byType(ListTile),
      );
      await tabTo(tester, result);
      expect(ringBorder(tester, result), ringBox(tester, result));
      expect(
        find.ancestor(
          of: key('destination-field'),
          matching: find.byType(FocusRing),
        ),
        findsNothing,
        reason: 'no ring is added around the field',
      );
    });

    testWidgets('ActionChip: "Use my current location"', (tester) async {
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
      await tester.enterText(key('manual-origin-field'), 'Tampines Hub');
      await tester.pump(pastSearchDebounce);
      await tester.pump();
      await tester.tap(find.text('OUR TAMPINES HUB'));
      await tester.pump();
      location.fix(bishan); // late: only offered
      await tester.pump();
      final chip = key('use-current-location');
      expect(chip, findsOneWidget);
      final stock = paintedSide(tester, chip);
      expect(ringBorder(tester, chip), isNull);
      await tabTo(tester, chip);
      expect(
        ringBorder(tester, chip),
        ringBox(tester, chip),
        reason: 'the shared ring around the chip',
      );
      expect(paintedSide(tester, chip), stock, reason: 'its own side: stock');
      await press(tester, LogicalKeyboardKey.tab);
      expect(ringBorder(tester, chip), isNull, reason: 'unfocused');
    });
  });

  group('T4: touch, mouse and hover', () {
    testWidgets('touch: focus moved by "Select" and Show/Hide map shows no '
        'ring; a key shows it at once, a touch hides it again', (tester) async {
      await journey(tester);
      await tapVisible(tester, key('select-option-F10'));
      final mark = key('selected-option-F10');
      expect(focusIn(mark), isTrue, reason: 'focus moved to the mark');
      expect(ringBorder(tester, mark), isNull);

      await tapVisible(tester, key('show-map'));
      expect(focusIn(key('hide-map')), isTrue);
      expect(paintedSide(tester, key('hide-map')), BorderSide.none);

      await press(tester, LogicalKeyboardKey.shiftLeft);
      expect(
        paintedSide(tester, key('hide-map')),
        ringAt(tester, key('hide-map')),
        reason: 'a key: traditional, the focused control rebuilds',
      );
      await touchEmpty(tester);
      expect(paintedSide(tester, key('hide-map')), BorderSide.none);
    });

    testWidgets('touch keeps OutlinedButton\'s stock 1 px primary focused '
        'border (D3)', (tester) async {
      await journey(tester);
      await tapVisible(tester, key('show-map'));
      await tapVisible(tester, key('hide-map'));
      expect(focusIn(key('show-map')), isTrue, reason: 'focus moved back');
      expect(
        paintedSide(tester, key('show-map')),
        BorderSide(color: primaryAt(tester, key('show-map'))),
      );
    });

    testWidgets('touch on a FocusLanding: no ring; a key shows it', (
      tester,
    ) async {
      await journey(tester);
      await tapVisible(tester, key('select-option-F10'));
      final mark = key('selected-option-F10');
      expect(ringBorder(tester, mark), isNull);
      await press(tester, LogicalKeyboardKey.shiftLeft);
      expect(ringBorder(tester, mark), ringBox(tester, mark));
    });

    testWidgets(
      'desktop mouse: hover alone and a press show no ring; a click that '
      'moves focus in code shows it (D1)',
      (tester) async {
        // One mouse device for the whole test, as on a desktop.
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        addTearDown(mouse.removePointer);
        Future<void> click(Finder f) async {
          await tester.ensureVisible(f);
          await tester.pump();
          final at = tester.getCenter(f);
          await mouse.moveTo(at);
          await mouse.down(at);
          await mouse.up();
          await tester.pump();
          await tester.pump();
        }

        await journey(tester, pick: click);
        final select = key('select-option-F10');
        await tester.ensureVisible(select);
        await tester.pump();
        final stock = paintedSide(tester, select);
        await mouse.moveTo(tester.getCenter(select));
        await tester.pump();
        expect(paintedSide(tester, select), stock, reason: 'hover alone');

        final refresh = key('refresh-conditions');
        await tester.ensureVisible(refresh);
        await tester.pump();
        await mouse.moveTo(tester.getCenter(refresh));
        await mouse.down(tester.getCenter(refresh));
        await tester.pump();
        expect(
          paintedSide(tester, refresh),
          BorderSide.none,
          reason: 'pressed',
        );
        await mouse.up();
        await tester.pump();

        await click(select);
        final mark = key('selected-option-F10');
        expect(focusIn(mark), isTrue);
        expect(ringBorder(tester, mark), ringBox(tester, mark));
        await click(key('show-map'));
        expect(
          paintedSide(tester, key('hide-map')),
          ringAt(tester, key('hide-map')),
        );
      },
      variant: desktop,
    );

    testWidgets(
      'desktop: after a touch, a mouse click keeps touch mode: no ring '
      '(Flutter 3.47.2)',
      (tester) async {
        await journey(tester, kind: PointerDeviceKind.mouse);
        await touchEmpty(tester);
        await tapVisible(
          tester,
          key('select-option-F10'),
          kind: PointerDeviceKind.mouse,
        );
        final mark = key('selected-option-F10');
        expect(focusIn(mark), isTrue);
        expect(ringBorder(tester, mark), isNull);
      },
      variant: desktop,
    );
  });

  group('T6–T8: menus, dialogs and theme changes', () {
    testWidgets('T6: palette menu items ring as the arrows move; Escape '
        'returns the ring to the palette button', (tester) async {
      await boot(tester);
      Finder option(AppPalette p) => key('palette-option-${p.id}').first;
      await tabTo(tester, key('palette-button'));
      await press(tester, LogicalKeyboardKey.enter);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(
        paintedSide(tester, option(AppPalette.teal)),
        ringAt(tester, option(AppPalette.teal)),
      );
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(
        paintedSide(tester, option(AppPalette.blue)),
        ringAt(tester, option(AppPalette.blue)),
      );
      expect(paintedSide(tester, option(AppPalette.teal)), BorderSide.none);
      await press(tester, LogicalKeyboardKey.escape);
      await tester.pump(const Duration(milliseconds: 300));
      expect(focusIn(key('palette-button')), isTrue);
      expect(
        paintedSide(tester, key('palette-button')),
        ringAt(tester, key('palette-button')),
      );
    });

    testWidgets('T7: About dialog actions ring; closing returns the ring to '
        'About; the licence page\'s back button rings, and E7 adds no ring '
        'to its package list (D4 limitation)', (tester) async {
      await boot(tester);
      await tabTo(tester, key('about-button'));
      await press(tester, LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 300));
      for (final label in ['View licenses', 'Close']) {
        final action = find.widgetWithText(TextButton, label);
        await tabTo(tester, action);
        expect(
          paintedSide(tester, action),
          ringAt(tester, action),
          reason: label,
        );
      }
      await press(tester, LogicalKeyboardKey.escape);
      await tester.pump(const Duration(milliseconds: 300));
      expect(focusIn(key('about-button')), isTrue);
      expect(
        paintedSide(tester, key('about-button')),
        ringAt(tester, key('about-button')),
      );

      await press(tester, LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 300));
      await tabTo(tester, find.widgetWithText(TextButton, 'View licenses'));
      await press(tester, LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 500));
      final back = find.byType(BackButton);
      expect(back, findsOneWidget);
      await tabTo(tester, back);
      expect(paintedSide(tester, back), ringAt(tester, back));
      expect(
        find.descendant(
          of: find.byType(LicensePage),
          matching: find.byType(FocusRing),
        ),
        findsNothing,
        reason: 'D4: the package list keeps Flutter\'s stock focus fill',
      );
    });

    testWidgets('T8: a palette chosen by keyboard and a light ↔ dark switch '
        'keep the ring, in the current primary on every frame', (tester) async {
      await boot(tester);
      final button = key('palette-button');
      await tabTo(tester, button);
      await press(tester, LogicalKeyboardKey.enter);
      for (var i = 0; i < 3; i++) {
        await press(tester, LogicalKeyboardKey.arrowDown); // teal, blue, rose
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      var framesFocused = 0;
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        if (focusIn(button)) framesFocused++;
        // The menu hands focus back in a post-frame callback, so the button
        // sees its focused state from the next frame on (as for Flutter's own
        // focus highlight).
        if (framesFocused < 2) continue;
        expect(
          paintedSide(tester, button),
          ringAt(tester, button),
          reason: '$i',
        );
      }
      expect(focusIn(button), isTrue);
      expect(
        paintedSide(tester, button).color,
        paletteTheme(AppPalette.rose, Brightness.light).colorScheme.primary,
      );

      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        expect(
          paintedSide(tester, button),
          ringAt(tester, button),
          reason: '$i',
        );
      }
      expect(
        paintedSide(tester, button).color,
        paletteTheme(AppPalette.rose, Brightness.dark).colorScheme.primary,
      );
    });
  });
}
