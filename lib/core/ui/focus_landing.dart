import 'package:flutter/material.dart';

import 'focus_highlight_scope.dart';
import 'focus_ring_theme.dart';

/// Where focus goes when the control the user pressed removes itself: a
/// Retry that turns into a spinner, "Select" that turns into "Selected"
/// (#56). Wraps something that stays, such as the section's title. Tab never
/// stops here, but from here the next Tab moves on in place (not from the
/// top). A ring shows while it has focus. It adds no screen-reader node of
/// its own: the node [child] belongs to (a tile, a heading) is the focused
/// one, so a screen reader moves there and its content is unchanged.
class FocusLanding extends StatelessWidget {
  const FocusLanding({super.key, required this.focusNode, required this.child});

  final FocusNode focusNode;
  final Widget child;

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: focusNode,
    skipTraversal: true,
    includeSemantics: false,
    child: ListenableBuilder(
      listenable: focusNode,
      builder: (context, child) {
        final focused = focusNode.hasPrimaryFocus;
        // `focused: false` would make that node focusable (a Tab stop on Web).
        return Semantics(
          focused: focused ? true : null,
          child: FocusRing(focused: focused, child: child!),
        );
      },
      child: child,
    ),
  );
}

/// A ring in the primary colour around [child] while [focused], when Flutter's
/// focus highlight mode is traditional (none for touch, as for the buttons'
/// ring: E7 D1). It rebuilds when the mode changes. [twoTone] adds a band in
/// the surface colour inside the ring, for a child of arbitrary colours such
/// as the map's tiles (E7 D2).
class FocusRing extends StatelessWidget {
  const FocusRing({
    super.key,
    required this.focused,
    this.twoTone = false,
    this.radius = 4,
    required this.child,
  });

  final bool focused;
  final bool twoTone;

  /// The corner radius, to follow the child's shape (a chip's is 8).
  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final show = focused && FocusHighlightScope.showsFocusOf(context);
    final scheme = Theme.of(context).colorScheme;
    final corners = BorderRadius.all(Radius.circular(radius));
    Widget ringed = child;
    if (twoTone) {
      // Drawn under the ring: the ring covers its outer half.
      ringed = DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border: show
              ? Border.all(
                  color: focusRingBandColor(scheme),
                  width: focusRingWidth * 2,
                )
              : null,
          borderRadius: corners,
        ),
        child: ringed,
      );
    }
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        border: show
            ? Border.all(color: focusRingColor(scheme), width: focusRingWidth)
            : null,
        borderRadius: corners,
      ),
      child: ringed,
    );
  }
}

/// A [FocusRing] around [child] while a control inside it has focus, for a
/// control with no focused border of its own (a `ListTile`, a bare
/// `InkWell`, a chip: see `withFocusRings`). It adds no Tab stop and no
/// semantics node.
class FocusRingWithin extends StatefulWidget {
  const FocusRingWithin({super.key, this.radius = 4, required this.child});

  final double radius;
  final Widget child;

  @override
  State<FocusRingWithin> createState() => _FocusRingWithinState();
}

class _FocusRingWithinState extends State<FocusRingWithin> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    includeSemantics: false,
    onFocusChange: (focused) => setState(() => _focused = focused),
    child: FocusRing(
      focused: _focused,
      radius: widget.radius,
      child: widget.child,
    ),
  );
}
