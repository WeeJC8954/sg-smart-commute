// The app mark in the app bar, beside the title.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/app/app.dart';
import 'package:sg_smart_commute/app/app_logo.dart';

import '../fakes/fake_environment_repository.dart';
import '../fakes/fake_location_service.dart';
import '../fakes/test_app.dart';

Future<void> pumpAt(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    buildTestApp(
      location: FakeLocationService(),
      environment: FakeEnvironmentRepository(),
    ),
  );
}

void main() {
  testWidgets('sits in the app bar, just before the title', (tester) async {
    await pumpAt(tester, const Size(1080, 2000));
    final logo = find.descendant(
      of: find.byType(AppBar),
      matching: find.byKey(const Key('app-logo')),
    );
    final title = find.descendant(
      of: find.byType(AppBar),
      matching: find.text(SmartCommuteApp.title),
    );
    expect(logo, findsOneWidget);
    expect(title, findsOneWidget);
    final logoBox = tester.getRect(logo);
    final titleBox = tester.getRect(title);
    expect(logoBox.size, const Size.square(28));
    expect(logoBox.right, lessThan(titleBox.left));
    expect(logoBox.center.dy, closeTo(titleBox.center.dy, 2));
  });

  testWidgets('uses the theme colours and is hidden from screen readers', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpAt(tester, const Size(1080, 2000));
    final scheme = Theme.of(tester.element(find.byKey(const Key('app-logo'))))
        .colorScheme;
    final paint = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byKey(const Key('app-logo')),
        matching: find.byType(CustomPaint),
      ),
    );
    final painter = paint.painter! as AppLogoPainter;
    expect(painter.tile, scheme.primary);
    expect(painter.mark, scheme.onPrimary);
    // The title is read once; the decorative mark adds nothing.
    expect(find.bySemanticsLabel(SmartCommuteApp.title), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a narrow phone: the title shortens instead of overflowing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            title: const AppTitle(),
            actions: [
              IconButton(onPressed: () {}, icon: const Icon(Icons.refresh)),
            ],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byKey(const Key('app-logo'))),
      const Size.square(28),
    );
    final title = tester.widget<Text>(find.text(SmartCommuteApp.title));
    expect(title.overflow, TextOverflow.ellipsis);
  });
}
