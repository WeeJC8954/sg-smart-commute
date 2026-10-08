import 'package:flutter/material.dart';

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

/// A ring in the primary colour around [child] while [focused], when the
/// user is on a keyboard (none for touch, as for Material's own buttons).
class FocusRing extends StatelessWidget {
  const FocusRing({super.key, required this.focused, required this.child});

  final bool focused;
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    position: DecorationPosition.foreground,
    decoration: BoxDecoration(
      border:
          focused &&
              FocusManager.instance.highlightMode ==
                  FocusHighlightMode.traditional
          ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2)
          : null,
      borderRadius: const BorderRadius.all(Radius.circular(4)),
    ),
    child: child,
  );
}
