import 'package:flutter/material.dart';

import 'focus_landing.dart';

/// A section title that screen readers expose as a heading, so TalkBack's
/// and VoiceOver's heading navigation can jump between sections. Its own
/// semantics node, so the heading flag never spreads to nearby text.
class SectionHeading extends StatelessWidget {
  const SectionHeading(this.text, {super.key, this.style, this.focusNode});

  final String text;
  final TextStyle? style;

  /// Makes the heading a [FocusLanding], for a control in its section that
  /// removes itself when pressed (#56).
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final title = Text(text, style: style);
    return Semantics(
      container: true,
      header: true,
      child: focusNode == null
          ? title
          : FocusLanding(focusNode: focusNode!, child: title),
    );
  }
}
