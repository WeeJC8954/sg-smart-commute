import 'package:flutter/material.dart';

void main() {
  runApp(const SmartCommuteApp());
}

/// Milestone 0 skeleton. Phase 1 features start in Milestone 1.
class SmartCommuteApp extends StatelessWidget {
  const SmartCommuteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Singapore Smart Commute',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      ),
      home: const Scaffold(
        body: Center(child: Text('Singapore Smart Commute')),
      ),
    );
  }
}
