import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/features/appearance/appearance_providers.dart';
import 'package:sg_smart_commute/features/appearance/domain/app_palette.dart';

import '../../../integration_test/fakes/fake_palette_store.dart';

void main() {
  ProviderContainer container(FakePaletteStore store, [AppPalette? start]) {
    final c = ProviderContainer(
      overrides: [
        paletteStoreProvider.overrideWithValue(store),
        if (start != null) initialPaletteProvider.overrideWithValue(start),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('starts from the initial palette, teal by default', () {
    expect(
      container(FakePaletteStore()).read(paletteProvider),
      AppPalette.teal,
    );
    expect(
      container(FakePaletteStore(), AppPalette.rose).read(paletteProvider),
      AppPalette.rose,
    );
  });

  test('select applies at once, then stores the id', () async {
    final store = FakePaletteStore();
    final c = container(store);
    final pending = c.read(paletteProvider.notifier).select(AppPalette.blue);
    expect(
      c.read(paletteProvider),
      AppPalette.blue,
      reason: 'before the write',
    );
    await pending;
    expect(store.writes, ['blue']);
  });

  test(
    'a failed write keeps the selection, throws nothing, stores nothing',
    () async {
      final store = FakePaletteStore(failWrite: true);
      final c = container(store);
      await c.read(paletteProvider.notifier).select(AppPalette.orange);
      expect(c.read(paletteProvider), AppPalette.orange);
      expect(store.stored, isNull);
      expect(store.writes, isEmpty);
    },
  );
}
