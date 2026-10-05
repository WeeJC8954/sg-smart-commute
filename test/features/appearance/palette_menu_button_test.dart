import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/app/home_screen.dart';
import 'package:sg_smart_commute/core/location/location_service.dart';
import 'package:sg_smart_commute/features/appearance/domain/app_palette.dart';
import 'package:sg_smart_commute/features/appearance/presentation/palette_menu_button.dart';
import 'package:sg_smart_commute/features/appearance/presentation/palette_theme.dart';

import '../../../integration_test/fakes/fake_environment_repository.dart';
import '../../../integration_test/fakes/fake_location_service.dart';
import '../../../integration_test/fakes/fake_palette_store.dart';
import '../../../integration_test/fakes/test_app.dart';

const button = Key('palette-button');

/// RadioMenuButton passes its key on to its MenuItemButton: two matches.
Finder option(AppPalette p) => find.byKey(Key('palette-option-${p.id}')).first;

bool menuOpen() =>
    find.byKey(const Key('palette-option-teal')).evaluate().isNotEmpty;

Widget app(FakePaletteStore store) => buildTestApp(
  location: FakeLocationService(access: LocationAccess.denied),
  environment: FakeEnvironmentRepository(),
  paletteStore: store,
);

ColorScheme scheme(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(HomeScreen))).colorScheme;

/// The palette option that has keyboard focus, 'button', or 'other'.
String focused() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return 'none';
  String? found;
  void check(Element e) {
    if (e.widget.key == button) found ??= 'button';
    final w = e.widget;
    if (w is RadioMenuButton<AppPalette>) found ??= 'option:${w.value.id}';
  }

  check(context as Element);
  context.visitAncestorElements((e) {
    check(e);
    return found == null;
  });
  return found ?? 'other';
}

Future<void> pumpTall(WidgetTester tester, Widget widget) async {
  tester.view.physicalSize = const Size(1080, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(widget);
  await tester.pump();
}

/// Choosing applies after the frame that closes the menu, then cross-fades.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  for (final b in Brightness.values) {
    testWidgets('${b.name}: five named options, each with its own swatch', (
      tester,
    ) async {
      tester.platformDispatcher.platformBrightnessTestValue = b;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await pumpTall(tester, app(FakePaletteStore()));
      await tester.tap(find.byKey(button));
      await tester.pump();
      for (final p in AppPalette.values) {
        expect(
          find.descendant(of: option(p), matching: find.text(p.label)),
          findsOneWidget,
        );
        final swatch = tester.widget<PaletteSwatch>(
          find.descendant(of: option(p), matching: find.byType(PaletteSwatch)),
        );
        expect(
          swatch.color,
          paletteTheme(p, b).colorScheme.primary,
          reason: p.id,
        );
      }
    });
  }

  testWidgets('semantics: a named button with its open state; radio options', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpTall(tester, app(FakePaletteStore()));
    expect(
      tester.getSemantics(find.byKey(button)),
      isSemantics(
        isButton: true,
        isEnabled: true,
        hasEnabledState: true,
        isFocusable: true,
        tooltip: 'Colour theme: Teal',
        hasExpandedState: true,
        isExpanded: false,
      ),
    );
    await tester.tap(find.byKey(button));
    await tester.pump();
    expect(
      tester.getSemantics(find.byKey(button)),
      isSemantics(hasExpandedState: true, isExpanded: true),
    );
    for (final p in AppPalette.values) {
      expect(
        tester.getSemantics(option(p)),
        matchesSemantics(
          label: p.label,
          hasCheckedState: true,
          isChecked: p == AppPalette.teal,
          isInMutuallyExclusiveGroup: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
        reason: p.id,
      );
    }
    semantics.dispose();
  });

  testWidgets('choosing applies at once, stores the id, closes the menu and '
      'renames the button', (tester) async {
    final store = FakePaletteStore();
    await pumpTall(tester, app(store));
    await tester.tap(find.byKey(button));
    await tester.pump();
    await tester.tap(option(AppPalette.rose));
    await settle(tester);
    expect(
      scheme(tester),
      paletteTheme(AppPalette.rose, Brightness.light).colorScheme,
    );
    expect(store.writes, ['rose']);
    expect(menuOpen(), isFalse);
    expect(
      tester.widget<IconButton>(find.byKey(button)).tooltip,
      PaletteMenuButton.tooltipFor(AppPalette.rose),
    );
    // The newly selected option now carries the checked state.
    await tester.tap(find.byKey(button));
    await tester.pump();
    final semantics = tester.ensureSemantics();
    expect(
      tester.getSemantics(option(AppPalette.rose)),
      isSemantics(isChecked: true),
    );
    expect(
      tester.getSemantics(option(AppPalette.teal)),
      isSemantics(isChecked: false),
    );
    semantics.dispose();
  });

  testWidgets(
    'keyboard: Tab, Enter, arrows, Enter; Space then Escape',
    (tester) async {
      final store = FakePaletteStore();
      await pumpTall(tester, app(store));
      Future<void> key(LogicalKeyboardKey k) async {
        await tester.sendKeyEvent(k);
        await tester.pump();
      }

      await key(LogicalKeyboardKey.tab);
      expect(focused(), 'button', reason: 'the first Tab stop');
      await key(LogicalKeyboardKey.enter);
      expect(menuOpen(), isTrue);
      await key(LogicalKeyboardKey.arrowDown);
      expect(focused(), 'option:teal');
      await key(LogicalKeyboardKey.arrowDown);
      expect(focused(), 'option:blue');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settle(tester);
      expect(
        scheme(tester),
        paletteTheme(AppPalette.blue, Brightness.light).colorScheme,
      );
      expect(menuOpen(), isFalse);
      expect(focused(), 'button', reason: 'focus returns to the button');

      await key(LogicalKeyboardKey.space);
      expect(menuOpen(), isTrue);
      await key(LogicalKeyboardKey.arrowDown);
      await key(LogicalKeyboardKey.escape);
      await tester.pump(const Duration(milliseconds: 300));
      expect(menuOpen(), isFalse);
      expect(store.writes, ['blue'], reason: 'Escape changes nothing');
      expect(focused(), 'button');
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.windows,
    }),
  );

  testWidgets('360 × 780 dp at 2× text: app bar and open menu fit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(app(FakePaletteStore()));
    await tester.pump();
    expect(tester.takeException(), isNull);
    final screen = Offset.zero & const Size(360, 780);
    bool onScreen(Rect r) =>
        screen.contains(r.topLeft) &&
        screen.contains(r.bottomRight - const Offset(1, 1));
    final b = tester.getRect(find.byKey(button));
    expect(onScreen(b), isTrue);
    expect(b.width, greaterThanOrEqualTo(48));
    expect(
      tester.getRect(find.text('Singapore Smart Commute')).right,
      lessThanOrEqualTo(b.left),
    );

    await tester.tap(find.byKey(button));
    await tester.pump();
    expect(tester.takeException(), isNull);
    for (final p in AppPalette.values) {
      expect(onScreen(tester.getRect(option(p))), isTrue, reason: p.id);
    }
  });
}
