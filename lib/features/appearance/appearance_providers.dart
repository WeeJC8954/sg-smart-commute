import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import 'data/shared_preferences_palette_store.dart';
import 'domain/app_palette.dart';
import 'domain/palette_store.dart';

/// The stored palette for startup: [AppPalette.fallback] when nothing is
/// stored, the id is unknown, the read fails or it takes longer than
/// [timeout]. Never throws, so storage can never stop or stall the app; a
/// result that arrives after [timeout] is ignored (it goes to an abandoned
/// future), so it never recolours the session that already started.
Future<AppPalette> loadInitialPalette(
  PaletteStore store, {
  Duration timeout = AppearanceConfig.paletteLoadTimeout,
}) async {
  try {
    return AppPalette.fromId(await store.read().timeout(timeout));
  } catch (e) {
    debugPrint('Colour palette not loaded: $e');
    return AppPalette.fallback;
  }
}

/// The palette read before the first frame; main() overrides it (E1).
final initialPaletteProvider = Provider<AppPalette>(
  (ref) => AppPalette.fallback,
);

/// Where the choice is remembered. Tests use a fake (buildTestApp).
final paletteStoreProvider = Provider<PaletteStore>(
  (ref) => SharedPreferencesPaletteStore(),
);

/// The one source of truth for the selected palette. Brightness stays the
/// system's; this only picks the colours.
final paletteProvider = NotifierProvider<PaletteController, AppPalette>(
  PaletteController.new,
);

class PaletteController extends Notifier<AppPalette> {
  @override
  AppPalette build() => ref.watch(initialPaletteProvider);

  /// Applies [palette] at once, then stores it. If the write fails the
  /// palette stays for this session; it is only not remembered (silent:
  /// a storage problem never interrupts the journey).
  Future<void> select(AppPalette palette) async {
    state = palette;
    try {
      await ref.read(paletteStoreProvider).write(palette.id);
    } catch (e) {
      debugPrint('Colour palette not saved: $e');
    }
  }
}
