import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../places/presentation/place_search_field.dart';
import '../domain/origin.dart';
import '../domain/origin_controller.dart';

/// Origin status, the manual-origin prompt and the late-fix offer (§5.1–§5.4).
class OriginCard extends ConsumerWidget {
  const OriginCard({super.key});

  static const String fallbackPrompt =
      "We couldn't determine your location. Where are you now?";

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(originControllerProvider);
    final controller = ref.read(originControllerProvider.notifier);
    final theme = Theme.of(context);

    final children = <Widget>[];
    switch (state.phase) {
      case OriginPhase.checkingPermission:
        children.add(const _Busy('Checking location permission…'));
      case OriginPhase.acquiring:
        children.add(const _Busy('Finding your location…'));
      case OriginPhase.ready:
        children.add(_OriginLine(origin: state.origin!));
        children.add(
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const Key('change-origin'),
              onPressed: controller.changeOrigin,
              child: const Text('Change'),
            ),
          ),
        );
      case OriginPhase.needsManual:
        final reason = state.fallbackReason;
        if (reason != null) {
          children
            ..add(Text(fallbackPrompt, style: theme.textTheme.titleMedium))
            ..add(Text(reason.message))
            ..add(_FallbackActions(reason: reason));
        } else {
          children.add(
            Text('Where are you now?', style: theme.textTheme.titleMedium),
          );
          if (state.origin != null) {
            children.add(_OriginLine(origin: state.origin!));
          }
        }
        children.add(const SizedBox(height: 8));
        children.add(
          PlaceSearchField(
            fieldKey: const Key('manual-origin-field'),
            label: 'Your location',
            onEditingStarted: controller.beginManualEntry,
            onSelected: (place) => controller.selectManualOrigin(
              place.displayName,
              place.position,
              detail: place.distinctAddress,
            ),
          ),
        );
    }

    if (state.offeredGpsFix != null) {
      children.add(
        Align(
          alignment: Alignment.centerLeft,
          child: ActionChip(
            key: const Key('use-current-location'),
            avatar: const Icon(Icons.my_location, size: 18),
            label: const Text('Use my current location'),
            onPressed: controller.useCurrentLocation,
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }
}

class _OriginLine extends StatelessWidget {
  const _OriginLine({required this.origin});
  final Origin origin;

  @override
  Widget build(BuildContext context) {
    final how = switch (origin.provenance) {
      OriginProvenance.gps => 'from GPS',
      OriginProvenance.manual => 'chosen manually',
    };
    final line = Row(
      children: [
        Icon(
          origin.provenance == OriginProvenance.gps
              ? Icons.my_location
              : Icons.place_outlined,
          size: 20,
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            'From: ${origin.label} ($how)',
            key: const Key('origin-line'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      ],
    );
    final detail = origin.detail;
    if (detail == null) return line;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        line,
        Text(detail, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _FallbackActions extends ConsumerWidget {
  const _FallbackActions({required this.reason});
  final LocationFailure reason;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(originControllerProvider.notifier);
    final canOpenSettings =
        !kIsWeb &&
        (reason is LocationPermissionPermanentlyDenied ||
            reason is LocationServiceDisabled);
    return Wrap(
      spacing: 8,
      children: [
        if (canOpenSettings)
          TextButton(
            onPressed: controller.openSettings,
            child: const Text('Open settings'),
          ),
        TextButton(
          onPressed: controller.retryLocation,
          child: const Text('Try location again'),
        ),
      ],
    );
  }
}

class _Busy extends StatelessWidget {
  const _Busy(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    child: Row(
      children: [
        const SizedBox.square(
          dimension: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 8),
        ExcludeSemantics(child: Text(label)),
      ],
    ),
  );
}
