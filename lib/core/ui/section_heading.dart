import 'package:flutter/material.dart';

/// A section title that screen readers expose as a heading, so TalkBack's
/// and VoiceOver's heading navigation can jump between sections. Its own
/// semantics node, so the heading flag never spreads to nearby text.
class SectionHeading extends StatelessWidget {
  const SectionHeading(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) =>
      Semantics(container: true, header: true, child: Text(text, style: style));
}
