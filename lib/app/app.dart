import 'package:flutter/material.dart';

import 'home_screen.dart';

/// Riverpod 3 retries failed providers automatically by default. That would
/// re-call rate-limited APIs in the background, so the app disables it and
/// offers explicit Retry actions instead. Pass to `ProviderScope.retry`.
Duration? noAutomaticRetry(int retryCount, Object error) => null;

class SmartCommuteApp extends StatelessWidget {
  const SmartCommuteApp({super.key});

  static const String title = 'Singapore Smart Commute';

  /// Light and dark schemes from one seed, so both stay the same palette.
  /// Widgets take colours only from the scheme, never fixed values.
  static final ThemeData lightTheme = _theme(Brightness.light);
  static final ThemeData darkTheme = _theme(Brightness.dark);

  static ThemeData _theme(Brightness brightness) => ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.teal,
      brightness: brightness,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: title,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}
