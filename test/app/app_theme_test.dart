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
}
