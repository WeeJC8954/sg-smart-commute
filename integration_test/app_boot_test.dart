// Harness check (M0): the real app builds and boots on the device/browser.
// Since M1 the app uses location and data.gov.sg, so even this boot test runs
// with fake providers: no integration test may call a live external API.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_environment_repository.dart';
import 'fakes/fake_location_service.dart';
import 'fakes/test_app.dart';
import 'support.dart';

void main() {
  initIntegrationTest();

  testWidgets('app boots to its shell', (tester) async {
    await tester.pumpWidget(
      buildTestApp(
        location: FakeLocationService(),
        environment: FakeEnvironmentRepository(),
      ),
    );
    await tester.pump();

    expect(find.text('Singapore Smart Commute'), findsOneWidget);
    await tester.tap(find.byKey(const Key('about-button')));
    await pumpUntilFound(tester, find.text('Author: Jaycee Wee'));
    expect(find.text('Version 9.8.7 (42)'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Author: Jaycee Wee'), findsNothing);
  });

  // E7: a keyboard Tab shows the 2 px primary focus ring, and only on the
  // focused control.
  // The physical key is given: on Web (dart2js) the key simulator cannot look
  // up Tab's USB code by itself (a null check fails).
  testWidgets('Tab shows the focus ring in the app bar', (tester) async {
    await tester.pumpWidget(
      buildTestApp(
        location: FakeLocationService(),
        environment: FakeEnvironmentRepository(),
      ),
    );
    await tester.pump();

    BorderSide side(String key) {
      final material = tester.widget<Material>(
        find
            .descendant(
              of: find.byKey(Key(key)),
              matching: find.byType(Material),
            )
            .first,
      );
      return (material.shape! as OutlinedBorder).side;
    }

    final primary = Theme.of(
      tester.element(find.byKey(const Key('about-button'))),
    ).colorScheme.primary;
    final ring = BorderSide(color: primary, width: 2);
    expect(side('about-button'), BorderSide.none);

    await tester.sendKeyEvent(
      LogicalKeyboardKey.tab,
      physicalKey: PhysicalKeyboardKey.tab,
    );
    await tester.pump();
    await tester.pump();
    expect(side('about-button'), ring);

    await tester.sendKeyEvent(
      LogicalKeyboardKey.tab,
      physicalKey: PhysicalKeyboardKey.tab,
    );
    await tester.pump();
    await tester.pump();
    expect(side('palette-button'), ring);
    expect(side('about-button'), BorderSide.none);
  });
}
