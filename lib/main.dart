import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'features/appearance/appearance_providers.dart';
import 'features/appearance/data/shared_preferences_palette_store.dart';

export 'app/app.dart' show SmartCommuteApp, noAutomaticRetry;

Future<void> main() async {
  // The stored palette is read before the first frame, so a chosen palette
  // never shows the default first (E1). The read is bounded and never
  // throws: on any problem the app starts in the default palette.
  WidgetsFlutterBinding.ensureInitialized();
  final palette = await loadInitialPalette(SharedPreferencesPaletteStore());
  runApp(
    ProviderScope(
      retry: noAutomaticRetry,
      overrides: [initialPaletteProvider.overrideWithValue(palette)],
      child: const SmartCommuteApp(),
    ),
  );
}
