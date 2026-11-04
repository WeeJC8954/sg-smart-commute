// E7 T5: FocusHighlightScope follows Flutter's own focus highlight mode
// (D1: no custom tracker), rebuilds what depends on it, and never takes an
// event away from focus traversal.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/core/ui/focus_highlight_scope.dart';

/// Records what [FocusHighlightScope.showsFocusOf] says on each build.
class _Probe extends StatelessWidget {
  const _Probe(this.seen);

  final List<bool> seen;

  @override
  Widget build(BuildContext context) {
    seen.add(FocusHighlightScope.showsFocusOf(context));
    return const SizedBox();
  }
}

void main() {
  tearDown(() {
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
  });

  testWidgets('a touch makes it false, a key event or a mouse makes it true, '
      'and each change rebuilds its dependants', (tester) async {
    final seen = <bool>[];
    await tester.pumpWidget(FocusHighlightScope(child: _Probe(seen)));
    await tester.tapAt(const Offset(5, 5)); // touch
    await tester.pump();
    expect(seen.last, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(seen.last, isTrue, reason: 'a key event: traditional');

    await tester.tapAt(const Offset(5, 5));
    await tester.pump();
    expect(seen.last, isFalse, reason: 'a touch: touch');

    await tester.tapAt(const Offset(5, 5), kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(seen.last, isTrue, reason: 'a mouse: traditional (D1)');
  });

  testWidgets('it reads FocusManager.highlightMode, also when the strategy '
      'forces it', (tester) async {
    final seen = <bool>[];
    await tester.pumpWidget(FocusHighlightScope(child: _Probe(seen)));
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    await tester.pump();
    expect(seen.last, isTrue);
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTouch;
    await tester.pump();
    expect(seen.last, isFalse);
  });

  testWidgets('no rebuild when the mode does not change', (tester) async {
    final seen = <bool>[];
    await tester.pumpWidget(FocusHighlightScope(child: _Probe(seen)));
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    await tester.pump();
    final builds = seen.length;
    await tester.sendKeyEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(seen.length, builds);
  });

  testWidgets('without a scope it falls back to FocusManager', (tester) async {
    final seen = <bool>[];
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    await tester.pumpWidget(_Probe(seen));
    expect(seen.last, isTrue);
  });

  testWidgets('its listener is removed on dispose', (tester) async {
    final seen = <bool>[];
    await tester.pumpWidget(FocusHighlightScope(child: _Probe(seen)));
    await tester.pumpWidget(const SizedBox());
    final builds = seen.length;
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTouch;
    await tester.pump();
    expect(seen.length, builds);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Tab still moves focus: no key event is consumed', (
    tester,
  ) async {
    final first = FocusNode(debugLabel: 'first');
    final second = FocusNode(debugLabel: 'second');
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: FocusHighlightScope(
          child: Column(
            children: [
              TextButton(
                focusNode: first,
                onPressed: () {},
                child: const Text('one'),
              ),
              TextButton(
                focusNode: second,
                onPressed: () {},
                child: const Text('two'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(first.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(second.hasPrimaryFocus, isTrue);
  });
}
