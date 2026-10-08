import 'package:flutter/material.dart';

/// A small spinner next to [label]. Screen readers hear the label once.
///
/// [compact] is for secondary, inline states (e.g. live arrivals under an
/// option): a smaller spinner and small text.
class BusyRow extends StatelessWidget {
  const BusyRow(this.label, {super.key, this.compact = false});

  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    child: Row(
      children: [
        SizedBox.square(
          dimension: compact ? 14 : 16,
          child: const CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: ExcludeSemantics(
            child: Text(
              label,
              style: compact ? Theme.of(context).textTheme.bodySmall : null,
            ),
          ),
        ),
      ],
    ),
  );
}

/// A failure message with an optional Retry button after it.
class ErrorRetryRow extends StatelessWidget {
  const ErrorRetryRow({
    super.key,
    required this.message,
    this.onRetry,
    this.retryLabel,
    this.liveRegion = false,
    this.landing,
  });

  final String message;

  /// Null when retrying cannot help: no button is shown.
  final VoidCallback? onRetry;

  /// Retry replaces this row with a spinner, so focus moves here first: the
  /// node of a `FocusLanding` on something that stays, such as the section's
  /// title (#56).
  final FocusNode? landing;

  /// What screen readers say for the button, e.g. "Retry 1-hr PM2.5": with
  /// several failures on screen, a bare "Retry" doesn't say which one it
  /// retries. The visible text stays "Retry".
  final String? retryLabel;

  /// Announce [message] when it appears, for a failure of something the
  /// user just did (a search, a refresh).
  final bool liveRegion;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Semantics(
          container: liveRegion,
          liveRegion: liveRegion,
          child: Text(message),
        ),
      ),
      if (onRetry != null)
        TextButton(
          onPressed: () {
            landing?.requestFocus();
            onRetry!();
          },
          child: Text('Retry', semanticsLabel: retryLabel),
        ),
    ],
  );
}
