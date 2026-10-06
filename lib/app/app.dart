import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/appearance/appearance_providers.dart';
import '../features/appearance/presentation/palette_theme.dart';
import 'home_screen.dart';

/// Riverpod 3 retries failed providers automatically by default. That would
/// re-call rate-limited APIs in the background, so the app disables it and
/// offers explicit Retry actions instead. Pass to `ProviderScope.retry`.
Duration? noAutomaticRetry(int retryCount, Object error) => null;

class SmartCommuteApp extends ConsumerWidget {
  const SmartCommuteApp({super.key});

  static const String title = 'Singapore Smart Commute';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(paletteProvider);
    return MaterialApp(
      title: title,
      theme: paletteTheme(palette, Brightness.light),
      darkTheme: paletteTheme(palette, Brightness.dark),
      // The palette is the user's; the brightness stays the system's.
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}
