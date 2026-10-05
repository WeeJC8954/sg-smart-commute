import 'package:flutter/foundation.dart';

import '../../core/config/app_config.dart';
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
