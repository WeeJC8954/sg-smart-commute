import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/core/config/app_config.dart';
import 'package:sg_smart_commute/core/ui/motion.dart';

/// A [MotionSize] around a box of 50 or 200 px height. [duration] overrides
/// [uiMotionDurationProvider]; null keeps the real [AppMotion.resize].
Widget host({
  required bool tall,
  bool reduceMotion = false,
  Duration? duration,
}) => ProviderScope(
  overrides: [
    if (duration != null) uiMotionDurationProvider.overrideWithValue(duration),
  ],
  child: MediaQuery(
    data: MediaQueryData(disableAnimations: reduceMotion),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: MotionSize(
          key: const Key('motion'),
          child: SizedBox(width: 100, height: tall ? 200 : 50),
        ),
      ),
    ),
  ),
);

double heightOf(WidgetTester tester) =>
    tester.getSize(find.byKey(const Key('motion'))).height;

void main() {
  final half = AppMotion.resize ~/ 2;

  testWidgets('grows to new content over AppMotion.resize', (tester) async {
    await tester.pumpWidget(host(tall: false));
    expect(heightOf(tester), 50);

    await tester.pumpWidget(host(tall: true));
    await tester.pump(half);
    expect(heightOf(tester), greaterThan(50));
    expect(heightOf(tester), lessThan(200));

    await tester.pumpAndSettle();
    expect(heightOf(tester), 200);
  });

  testWidgets('interrupt: a change mid-animation continues from the '
      'current size', (tester) async {
    await tester.pumpWidget(host(tall: false));
    await tester.pumpWidget(host(tall: true));
    await tester.pump(half);
    final mid = heightOf(tester);

    await tester.pumpWidget(host(tall: false)); // reverse half-way
    await tester.pump(const Duration(milliseconds: 16));
    expect(heightOf(tester), lessThanOrEqualTo(mid)); // no jump to 200
    expect(heightOf(tester), greaterThan(50)); // no jump to 50

    await tester.pumpAndSettle();
    expect(heightOf(tester), 50);
  });

  testWidgets('reduce motion: the change lands in one frame', (tester) async {
    await tester.pumpWidget(host(tall: false, reduceMotion: true));
    await tester.pumpWidget(host(tall: true, reduceMotion: true));
    expect(heightOf(tester), 200);
  });

  testWidgets('switching reduce motion while the app runs keeps the '
      "child's state (e.g. text typed in a search field)", (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    Widget field({required bool reduceMotion}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: ProviderScope(
          child: Material(
            child: MotionSize(child: _StatefulField(controller: controller)),
          ),
        ),
      ),
    );
    await tester.pumpWidget(field(reduceMotion: false));
    await tester.enterText(find.byType(TextField), 'Vivo');
    final state = tester.state(find.byType(_StatefulField));

    await tester.pumpWidget(field(reduceMotion: true));
    expect(tester.state(find.byType(_StatefulField)), same(state));
    await tester.pumpWidget(field(reduceMotion: false));
    expect(tester.state(find.byType(_StatefulField)), same(state));
    expect(find.text('Vivo'), findsOneWidget);
  });

  testWidgets('a zero duration override (tests) also lands in one frame', (
    tester,
  ) async {
    await tester.pumpWidget(host(tall: false, duration: Duration.zero));
    await tester.pumpWidget(host(tall: true, duration: Duration.zero));
    expect(heightOf(tester), 200);
  });
}

/// A stateful child, so a test can tell a kept State from a rebuilt one.
class _StatefulField extends StatefulWidget {
  const _StatefulField({required this.controller});
  final TextEditingController controller;

  @override
  State<_StatefulField> createState() => _StatefulFieldState();
}

class _StatefulFieldState extends State<_StatefulField> {
  @override
  Widget build(BuildContext context) =>
      TextField(controller: widget.controller);
}
