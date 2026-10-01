import 'package:flutter_test/flutter_test.dart';

import 'package:sg_smart_commute/main.dart';

void main() {
  testWidgets('skeleton app renders its title', (tester) async {
    await tester.pumpWidget(const SmartCommuteApp());

    expect(find.text('Singapore Smart Commute'), findsOneWidget);
  });
}
