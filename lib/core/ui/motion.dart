import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';

/// How long [MotionSize] animates. Tests override it with [Duration.zero]
/// so a layout change lands in one frame (`buildTestApp`).
final uiMotionDurationProvider = Provider<Duration>((ref) => AppMotion.resize);

/// Decelerates into place with no overshoot: the curve form of a critically
/// damped spring, so content settles instead of bouncing. Kept here, not in
/// app_config.dart, because a Curve is a Flutter type and app_config.dart is
/// pure Dart.
const Curve motionCurve = Curves.easeOutCubic;

/// Animates [child]'s height when its content changes, from the top edge.
/// Growing, new content unfolds below what caused it as the box grows.
/// Shrinking, the child takes its new size at once (removed content goes in
/// that frame) and only the freed space below closes over the duration.
/// A later change mid-animation continues from the current on-screen size,
/// but content that changes again on the very next layout (data landing on
/// consecutive frames) makes [AnimatedSize] jump to each new size until it
/// holds for a frame, so such a burst lands at once. With the system's
/// reduce-motion setting on, changes are instant.
///
/// Wrap a whole card, once. Never nest one inside another: the outer one
/// would chase the inner one's animated size.
class MotionSize extends ConsumerStatefulWidget {
  const MotionSize({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<MotionSize> createState() => _MotionSizeState();
}

class _MotionSizeState extends ConsumerState<MotionSize> {
  /// Moves [MotionSize.child] in or out of the [AnimatedSize] without
  /// rebuilding it, so switching reduce motion keeps what the user typed.
  final _childKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final duration = reduceMotion
        ? Duration.zero
        : ref.watch(uiMotionDurationProvider);
    final child = KeyedSubtree(key: _childKey, child: widget.child);
    // AnimatedSize asserts with a zero duration (its controller completes
    // inside its own layout), so an instant change uses none at all.
    if (duration == Duration.zero) return child;
    return AnimatedSize(
      duration: duration,
      curve: motionCurve,
      alignment: Alignment.topCenter,
      child: child,
    );
  }
}
