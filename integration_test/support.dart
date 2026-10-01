import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps frames until [finder] matches or [timeout] elapses. Used instead of
/// pumpAndSettle, which never settles while a progress indicator animates.
Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final end = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty) {
    if (DateTime.now().isAfter(end)) {
      throw TestFailure('Timed out waiting for $finder');
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Finder inTile(String key, String text) =>
    find.descendant(of: find.byKey(Key(key)), matching: find.text(text));

Future<void> scrollToAndTap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
}

/// Scrolls the home list back to the top, so the origin and destination
/// cards are built again (the list is lazy).
Future<void> scrollToTop(WidgetTester tester) async {
  await tester.drag(find.byType(Scrollable).first, const Offset(0, 5000));
  await tester.pump(const Duration(milliseconds: 300));
}

/// Types [query] into a place-search field, waits for the (fake) result
/// named [result] and taps it. Nothing is selected without the tap.
Future<void> searchAndPick(
  WidgetTester tester, {
  required Key field,
  required String query,
  required String result,
}) async {
  final input = find.byKey(field);
  await tester.ensureVisible(input);
  await tester.pump();
  await tester.enterText(input, query);
  await pumpUntilFound(tester, find.text(result));
  await scrollToAndTap(tester, find.text(result));
  await scrollToTop(tester);
}
