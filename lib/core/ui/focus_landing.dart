import 'package:flutter/material.dart';

/// Where focus goes when the control the user pressed removes itself: a
/// Retry that turns into a spinner, "Select" that turns into "Selected"
/// (#56). Wraps something that stays, such as the section's title. Tab never
/// stops here, but from here the next Tab moves on in place (not from the
/// top), and a screen reader reads [child]. A ring shows while it has focus.
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
        // One node, so the focused node is the one that has the label.
        // `focused: false` would make it focusable (a Tab stop on Web).
        return MergeSemantics(
          child: Semantics(
            focused: focused ? true : null,
            child: FocusRing(focused: focused, child: child!),
          ),
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
