import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/app/app.dart';
import 'package:sg_smart_commute/app/home_screen.dart';
import 'package:sg_smart_commute/core/location/location_service.dart';

import '../../integration_test/fakes/fake_environment_repository.dart';
import '../../integration_test/fakes/fake_location_service.dart';
import '../../integration_test/fakes/test_app.dart';

void main() {
  test('light and dark themes share the teal seed', () {
    expect(SmartCommuteApp.lightTheme.brightness, Brightness.light);
    expect(SmartCommuteApp.darkTheme.brightness, Brightness.dark);
    expect(
      SmartCommuteApp.darkTheme.colorScheme,
      ColorScheme.fromSeed(seedColor: Colors.teal, brightness: Brightness.dark),
    );
  });

  for (final brightness in Brightness.values) {
    testWidgets('the app follows a ${brightness.name} system setting', (
      tester,
    ) async {
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpWidget(
        buildTestApp(
          location: FakeLocationService(access: LocationAccess.denied),
          environment: FakeEnvironmentRepository(),
        ),
      );
      await tester.pump();
      final context = tester.element(find.byType(HomeScreen));
      expect(Theme.of(context).brightness, brightness);
    });
  }

  test('lib/ takes its colours from the theme scheme; the teal seed is the '
      'one fixed colour', () {
    // Colors.x, Color(…) and Color.from…(…) in code; text after `//` is
    // dropped as a comment. ponytail: a line scan, not a Dart parser — `//`
    // inside a string hides the rest of that line, and a /* block */ comment
    // is scanned. Add a parser only if that ever misleads.
    final fixed = RegExp(r'Colors\s*\.\s*\w+|\bColor\s*(?:\.\s*from\w*\s*)?\(');
    final found = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final code = file
          .readAsLinesSync()
          .map((line) => line.split('//').first)
          .join('\n');
      final path = file.path.replaceAll(r'\', '/');
      for (final m in fixed.allMatches(code)) {
        final line = '\n'.allMatches(code.substring(0, m.start)).length + 1;
        found.add('$path:$line ${m[0]}');
      }
    }
    final seed = RegExp(r'^lib/app/app\.dart:\d+ Colors\.teal$');
    expect(found.where(seed.hasMatch), hasLength(1), reason: 'the seed');
    expect(
      found.where((f) => !seed.hasMatch(f)),
      isEmpty,
      reason: 'take colours from Theme.of(context).colorScheme',
    );
  });
}
