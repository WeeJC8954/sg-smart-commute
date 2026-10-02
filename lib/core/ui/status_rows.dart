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
        ExcludeSemantics(
          child: Text(
            label,
            style: compact ? Theme.of(context).textTheme.bodySmall : null,
          ),
        ),
      ],
    ),
  );
}

/// A failure message with an optional Retry button after it.
class ErrorRetryRow extends StatelessWidget {
  const ErrorRetryRow({super.key, required this.message, this.onRetry});

  final String message;

  /// Null when retrying cannot help: no button is shown.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Text(message)),
      if (onRetry != null)
        TextButton(onPressed: onRetry, child: const Text('Retry')),
    ],
  );
}
