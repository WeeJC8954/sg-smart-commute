// The app icon in the app bar, beside the title.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/app/app.dart';
import 'package:sg_smart_commute/app/app_logo.dart';

import '../../integration_test/fakes/fake_environment_repository.dart';
import '../../integration_test/fakes/fake_location_service.dart';
import '../../integration_test/fakes/test_app.dart';

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
    expect(logoBox.size, const Size.square(32));
    expect(logoBox.right, lessThan(titleBox.left));
    expect(logoBox.center.dy, closeTo(titleBox.center.dy, 2));
  });

  testWidgets('shows the bundled icon PNG, hidden from screen readers', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpAt(tester, const Size(1080, 2000));
    final image = tester.widget<Image>(
      find.descendant(
        of: find.byKey(const Key('app-logo')),
        matching: find.byType(Image),
      ),
    );
    expect(image.image, isA<AssetImage>());
    expect((image.image as AssetImage).assetName, AppLogo.asset);
    // The title is read once; the decorative icon adds nothing.
    expect(find.bySemanticsLabel(SmartCommuteApp.title), findsOneWidget);
    semantics.dispose();
  });

  test('the asset is bundled, square and 192 px', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final data = await rootBundle.load(AppLogo.asset);
    final bytes = data.buffer.asUint8List();
    // PNG signature, then the IHDR width and height (big-endian).
    expect(bytes.sublist(1, 4), 'PNG'.codeUnits);
    int u32(int at) =>
        bytes[at] << 24 |
        bytes[at + 1] << 16 |
        bytes[at + 2] << 8 |
        bytes[at + 3];
    expect(u32(16), 192);
    expect(u32(20), 192);
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
      const Size.square(32),
    );
    final title = tester.widget<Text>(find.text(SmartCommuteApp.title));
    expect(title.overflow, TextOverflow.ellipsis);
  });
}
