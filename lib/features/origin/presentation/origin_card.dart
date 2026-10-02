import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/ui/status_rows.dart';
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
        children.add(const BusyRow('Checking location permission…'));
      case OriginPhase.acquiring:
        children.add(const BusyRow('Finding your location…'));
      case OriginPhase.ready:
        final origin = state.origin!;
        final manual = origin.provenance == OriginProvenance.manual;
        children.add(_OriginLine(origin: origin));
        children.add(
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                key: const Key('change-origin'),
                onPressed: controller.changeOrigin,
                child: const Text('Change'),
              ),
              // GPS can be retried at any time behind a manual origin; the
              // fix is only offered, never applied (docs/assumptions.md).
              if (manual)
                TextButton(
                  key: const Key('retry-location'),
                  onPressed: state.locatingInBackground
                      ? null
                      : controller.retryLocation,
                  child: const Text('Try location again'),
                ),
            ],
          ),
        );
        if (manual && state.locatingInBackground) {
          children.add(const BusyRow('Finding your location…', compact: true));
        }
        final failure = state.backgroundFailure;
        if (manual && failure != null) {
          children.add(
            Text(
              '${locationFailureText(failure, isWeb: kIsWeb)} '
              'Your chosen origin is kept.',
              key: const Key('background-location-failure'),
              style: theme.textTheme.bodySmall,
            ),
          );
        }
      case OriginPhase.needsManual:
        final reason = state.fallbackReason;
        if (reason != null) {
          children
            ..add(Text(fallbackPrompt, style: theme.textTheme.titleMedium))
            ..add(Text(locationFailureText(reason, isWeb: kIsWeb)))
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
        // Opened with "Change": the current origin can be kept.
        if (reason == null && state.origin != null) {
          children.add(
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const Key('keep-origin'),
                onPressed: controller.cancelChange,
                child: const Text('Keep this origin'),
              ),
            ),
          );
        }
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

/// User-facing text for a location failure. On Web, geolocator reports any
/// error of the browser's location request (blocked, position unavailable,
/// OS location off) as "permanently denied", and there is no settings deep
/// link, so the Web wording covers both and points to the site settings.
String locationFailureText(LocationFailure reason, {required bool isWeb}) =>
    switch (reason) {
      LocationPermissionPermanentlyDenied() when isWeb =>
        'Location is blocked or unavailable in this browser. You can allow it '
            "in the site's settings.",
      _ => reason.message,
    };

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
