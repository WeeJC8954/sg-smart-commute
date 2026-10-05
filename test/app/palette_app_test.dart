import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/app/home_screen.dart';
import 'package:sg_smart_commute/core/location/location_service.dart';
import 'package:sg_smart_commute/features/appearance/appearance_providers.dart';
import 'package:sg_smart_commute/features/appearance/domain/app_palette.dart';
import 'package:sg_smart_commute/features/appearance/presentation/palette_theme.dart';

import '../../integration_test/fakes/fake_environment_repository.dart';
import '../../integration_test/fakes/fake_location_service.dart';
import '../../integration_test/fakes/fake_palette_store.dart';
import '../../integration_test/fakes/test_app.dart';

Widget app(FakePaletteStore store, AppPalette palette) => buildTestApp(
  location: FakeLocationService(access: LocationAccess.denied),
  environment: FakeEnvironmentRepository(),
  paletteStore: store,
  palette: palette,
);

ColorScheme scheme(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(HomeScreen))).colorScheme;

Color primaryOf(AppPalette p) =>
    paletteTheme(p, Brightness.light).colorScheme.primary;

Future<void> select(WidgetTester tester, AppPalette p) async {
  final c = ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
  await c.read(paletteProvider.notifier).select(p);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300)); // theme cross-fade
}

/// The primary colour on each of 16 frames of 16 ms after choosing [p].
Future<List<Color>> framesAfterChoosing(
  WidgetTester tester,
  AppPalette p,
) async {
  final c = ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
  await c.read(paletteProvider.notifier).select(p);
  final seen = <Color>[];
  for (var i = 0; i < 16; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    seen.add(scheme(tester).primary);
  }
  return seen;
}

void setBrightness(WidgetTester tester, Brightness b) {
  tester.platformDispatcher.platformBrightnessTestValue = b;
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
}

void main() {
  for (final p in AppPalette.values) {
    for (final b in Brightness.values) {
      testWidgets('stored ${p.id}: the app starts in ${p.label}, ${b.name}', (
        tester,
      ) async {
        setBrightness(tester, b);
        final store = FakePaletteStore(stored: p.id);
        await tester.pumpWidget(app(store, await loadInitialPalette(store)));
        await tester.pump();
        expect(scheme(tester), paletteTheme(p, b).colorScheme);
      });
    }
  }

  testWidgets('nothing stored, or a failing read: teal, and the app starts', (
    tester,
  ) async {
    for (final store in [
      FakePaletteStore(),
      FakePaletteStore(failRead: true),
    ]) {
      await tester.pumpWidget(app(store, await loadInitialPalette(store)));
      await tester.pump();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(scheme(tester).primary, primaryOf(AppPalette.teal));
      await tester.pumpWidget(const SizedBox());
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('each palette can be chosen and recolours the app', (
    tester,
  ) async {
    await tester.pumpWidget(app(FakePaletteStore(), AppPalette.teal));
    await tester.pump();
    for (final p in AppPalette.values.reversed) {
      await select(tester, p);
      expect(
        scheme(tester),
        paletteTheme(p, Brightness.light).colorScheme,
        reason: p.id,
      );
    }
  });

  testWidgets('the system switching to dark keeps the chosen palette', (
    tester,
  ) async {
    setBrightness(tester, Brightness.light);
    await tester.pumpWidget(app(FakePaletteStore(), AppPalette.teal));
    await tester.pump();
    await select(tester, AppPalette.purple);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      scheme(tester),
      paletteTheme(AppPalette.purple, Brightness.dark).colorScheme,
    );
  });

  testWidgets('a restart restores the chosen palette', (tester) async {
    final store = FakePaletteStore();
    await tester.pumpWidget(app(store, await loadInitialPalette(store)));
    await tester.pump();
    await select(tester, AppPalette.rose);
    expect(store.stored, 'rose');

    await tester.pumpWidget(const SizedBox()); // the old ProviderScope is gone
    await tester.pumpWidget(app(store, await loadInitialPalette(store)));
    await tester.pump();
    expect(scheme(tester).primary, primaryOf(AppPalette.rose));
  });

  testWidgets('a failed write keeps the palette and the app usable', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(FakePaletteStore(failWrite: true), AppPalette.teal),
    );
    await tester.pump();
    await select(tester, AppPalette.rose);
    expect(scheme(tester).primary, primaryOf(AppPalette.rose));
    expect(
      find.byType(SnackBar),
      findsNothing,
      reason: 'a failed save is silent (D6)',
    );
    await tester.enterText(
      find.byKey(const Key('manual-origin-field')),
      'Vivo',
    );
    await tester.pump();
    expect(find.text('Vivo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('after a failed write, a restart shows what storage really '
      'holds', (tester) async {
    final store = FakePaletteStore(stored: 'blue', failWrite: true);
    await tester.pumpWidget(app(store, await loadInitialPalette(store)));
    await tester.pump();
    expect(scheme(tester).primary, primaryOf(AppPalette.blue));
    await select(tester, AppPalette.orange);
    expect(
      scheme(tester).primary,
      primaryOf(AppPalette.orange),
      reason: 'kept in memory',
    );
    expect(store.stored, 'blue', reason: 'nothing pretends it was saved');

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app(store, await loadInitialPalette(store)));
    await tester.pump();
    expect(scheme(tester).primary, primaryOf(AppPalette.blue));
  });

  testWidgets('a read that completes after startup never recolours the '
      'running app', (tester) async {
    final lateRead = Completer<String?>();
    final store = FakePaletteStore(pendingRead: lateRead);
    // Startup timed out (Task 2's fakeAsync test): the app runs in teal.
    await tester.pumpWidget(app(store, AppPalette.teal));
    await tester.pump();
    lateRead.complete('purple');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(scheme(tester).primary, primaryOf(AppPalette.teal));
    expect(store.reads, 0, reason: 'only startup reads the store');
  });

  testWidgets('normal motion: the palette change cross-fades (Material '
      'default)', (tester) async {
    await tester.pumpWidget(app(FakePaletteStore(), AppPalette.teal));
    await tester.pump();
    final seen = await framesAfterChoosing(tester, AppPalette.rose);
    final between = seen.where(
      (c) => c != primaryOf(AppPalette.rose) && c != primaryOf(AppPalette.teal),
    );
    expect(between, isNotEmpty);
    expect(seen.last, primaryOf(AppPalette.rose));
  });

  testWidgets('reduce motion: the palette change has no in-between colours', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(app(FakePaletteStore(), AppPalette.teal));
    await tester.pump();
    final seen = await framesAfterChoosing(tester, AppPalette.rose);
    expect(
      seen.where(
        (c) =>
            c != primaryOf(AppPalette.rose) && c != primaryOf(AppPalette.teal),
      ),
      isEmpty,
    );
    expect(seen.skip(1), everyElement(primaryOf(AppPalette.rose)));
  });
}
