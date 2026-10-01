import 'package:flutter/material.dart';

import 'home_screen.dart';

/// Riverpod 3 retries failed providers automatically by default. That would
/// re-call rate-limited APIs in the background, so the app disables it and
/// offers explicit Retry actions instead. Pass to `ProviderScope.retry`.
Duration? noAutomaticRetry(int retryCount, Object error) => null;

class SmartCommuteApp extends StatelessWidget {
  const SmartCommuteApp({super.key});

  static const String title = 'Singapore Smart Commute';

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: title,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      ),
      home: const HomeScreen(),
    );
  }
}
