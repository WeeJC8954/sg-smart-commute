// Harness check (M0): the real app builds and boots on the device/browser.
// Since M1 the app uses location and data.gov.sg, so even this boot test runs
// with fake providers: no integration test may call a live external API.
import 'package:flutter/widgets.dart';
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
}
