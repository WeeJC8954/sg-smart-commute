// Milestone 0 harness check: proves integration tests build and run on
// Android and Web. The Phase 1 happy-path and fallback/error-path tests
// (guide v2.1 §18) are added alongside their features and use fake
// providers only; no test here may call a live external API.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:sg_smart_commute/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app boots to its shell', (tester) async {
    await tester.pumpWidget(const SmartCommuteApp());
    await tester.pumpAndSettle();

    expect(find.text('Singapore Smart Commute'), findsOneWidget);
  });
}
