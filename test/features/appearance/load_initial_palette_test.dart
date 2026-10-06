import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/core/config/app_config.dart';
import 'package:sg_smart_commute/features/appearance/appearance_providers.dart';
import 'package:sg_smart_commute/features/appearance/data/shared_preferences_palette_store.dart';
import 'package:sg_smart_commute/features/appearance/domain/app_palette.dart';

import '../../../integration_test/fakes/fake_palette_store.dart';

void main() {
  for (final p in AppPalette.values) {
    test('stored ${p.id} → ${p.label}', () async {
      expect(await loadInitialPalette(FakePaletteStore(stored: p.id)), p);
    });
  }

  test('nothing stored → teal', () async {
    expect(await loadInitialPalette(FakePaletteStore()), AppPalette.teal);
  });

  test('an unknown id → teal, and the stored value is left alone', () async {
    final store = FakePaletteStore(stored: 'indigo');
    expect(await loadInitialPalette(store), AppPalette.teal);
    expect(store.stored, 'indigo');
    expect(store.writes, isEmpty);
  });

  test('a failing read → teal, no exception', () async {
    expect(
      await loadInitialPalette(FakePaletteStore(failRead: true)),
      AppPalette.teal,
    );
  });

  test('a read that never completes → teal at the timeout, not before', () {
    expect(
      AppearanceConfig.paletteLoadTimeout,
      const Duration(milliseconds: 500),
    );
    fakeAsync((async) {
      AppPalette? got;
      loadInitialPalette(FakePaletteStore(pendingRead: Completer<String?>()))
          .then((p) => got = p);
      async.elapse(const Duration(milliseconds: 499));
      expect(got, isNull);
      async.elapse(const Duration(milliseconds: 1));
      expect(got, AppPalette.teal);
    });
  });

  test(
    'a read that completes after the timeout does not change the result',
    () {
      fakeAsync((async) {
        final lateRead = Completer<String?>();
        AppPalette? got;
        loadInitialPalette(FakePaletteStore(pendingRead: lateRead))
            .then((p) => got = p);
        async.elapse(const Duration(milliseconds: 500));
        expect(got, AppPalette.teal);
        lateRead.complete('purple'); // arrives too late
        async.elapse(const Duration(seconds: 1));
        expect(got, AppPalette.teal);
      });
    },
  );

  test('the shared_preferences store without a platform implementation: its '
      'calls fail as Futures, so startup falls back to teal', () async {
    final store = SharedPreferencesPaletteStore(); // must not throw here
    await expectLater(store.read(), throwsA(anything));
    await expectLater(store.write('blue'), throwsA(anything));
    expect(await loadInitialPalette(store), AppPalette.teal);
  });
}
