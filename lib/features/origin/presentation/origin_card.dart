import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/ui/focus_landing.dart';
import '../../../core/ui/section_heading.dart';
import '../../../core/ui/status_rows.dart';
import '../../places/presentation/place_search_field.dart';
import '../domain/origin.dart';
import '../domain/origin_controller.dart';

/// The origin section of the route card (lib/app/route_card.dart): status,
/// the manual-origin prompt and the late-fix offer (§5.1–§5.4).
///
/// Focus follows the flow: "Change" opens a focused search field, and
/// picking a place (or "Keep this origin") puts focus on the new "Change", so
/// keyboard and screen-reader users are not sent back to the top.
class OriginCard extends ConsumerStatefulWidget {
  const OriginCard({super.key});

  static const String fallbackPrompt =
      "We couldn't determine your location. Where are you now?";

  @override
  ConsumerState<OriginCard> createState() => _OriginCardState();
}

class _OriginCardState extends ConsumerState<OriginCard> {
  final _changeButton = FocusNode(debugLabel: 'change-origin');

  /// Where the fallback prompt's "Try location again" leaves focus: the
  /// section itself, which stays while the prompt turns into a spinner (#65).
  final _section = FocusNode(debugLabel: 'origin-section');

  /// Set by that "Try location again" until its attempt settles, so a fix it
  /// gets is announced once (#65). A failure is announced by its own line.
  bool _announceFix = false;

  @override
  void dispose() {
    _changeButton.dispose();
    _section.dispose();
    super.dispose();
  }

  void _retryFromFallback() {
    _section.requestFocus();
    _announceFix = true;
    ref.read(originControllerProvider.notifier).retryLocation();
  }

  /// Focuses "Change" once the rebuild that shows it has run.
  void _focusChangeAfterRebuild() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _changeButton.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(originControllerProvider);
    final controller = ref.read(originControllerProvider.notifier);
    final theme = Theme.of(context);
    final announceFix = _announceFix && state.phase == OriginPhase.ready;
    if (state.phase case OriginPhase.ready || OriginPhase.needsManual) {
      _announceFix = false; // settled: once only
    }

    final children = <Widget>[];
    switch (state.phase) {
      case OriginPhase.checkingPermission:
        children.add(const BusyRow('Checking location permission…'));
      case OriginPhase.acquiring:
        children.add(const BusyRow('Finding your location…'));
      case OriginPhase.ready:
        final origin = state.origin!;
        final manual = origin.provenance == OriginProvenance.manual;
        children.add(_OriginLine(origin: origin, announce: announceFix));
        children.add(
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                key: const Key('change-origin'),
                focusNode: _changeButton,
                onPressed: controller.changeOrigin,
                // The destination has a "Change" too.
                child: const Text('Change', semanticsLabel: 'Change origin'),
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
        // The outcome of "Try location again" arrives later, away from
        // focus, so it is announced (#57), as is the chip below.
        final failure = state.backgroundFailure;
        if (manual && failure != null) {
          children.add(
            Semantics(
              container: true,
              liveRegion: true,
              child: Text(
                '${locationFailureText(failure, isWeb: kIsWeb)} '
                'Your chosen origin is kept.',
                key: const Key('background-location-failure'),
                style: theme.textTheme.bodySmall,
              ),
            ),
          );
        }
      case OriginPhase.needsManual:
        final reason = state.fallbackReason;
        if (reason != null) {
          children
            ..add(
              SectionHeading(
                OriginCard.fallbackPrompt,
                style: theme.textTheme.titleMedium,
              ),
            )
            // Also the outcome of "Try location again", which arrives away
            // from focus, so it is announced (#65).
            ..add(
              Semantics(
                container: true,
                liveRegion: true,
                child: Text(locationFailureText(reason, isWeb: kIsWeb)),
              ),
            )
            ..add(
              _FallbackActions(reason: reason, onRetry: _retryFromFallback),
            );
        } else {
          children.add(
            SectionHeading(
              'Where are you now?',
              style: theme.textTheme.titleMedium,
            ),
          );
          if (state.origin != null) {
            children.add(_OriginLine(origin: state.origin!));
          }
        }
        // Opened with "Change": the current origin can be kept.
        final changing = reason == null && state.origin != null;
        children.add(const SizedBox(height: 8));
        children.add(
          PlaceSearchField(
            fieldKey: const Key('manual-origin-field'),
            label: 'Your location',
            // Focused only when the user asked for it; the launch fallback
            // prompt doesn't pop the keyboard unasked.
            autofocus: changing,
            onEditingStarted: controller.beginManualEntry,
            onSelected: (place) {
              controller.selectManualOrigin(
                place.displayName,
                place.position,
                detail: place.distinctAddress,
              );
              _focusChangeAfterRebuild();
            },
          ),
        );
        if (changing) {
          children.add(
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const Key('keep-origin'),
                onPressed: () {
                  controller.cancelChange();
                  _focusChangeAfterRebuild();
                },
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
          // Merged, so the live region carries the chip's label: that is
          // what is announced.
          child: MergeSemantics(
            child: Semantics(
              liveRegion: true,
              child: ActionChip(
                key: const Key('use-current-location'),
                avatar: const Icon(Icons.my_location, size: 18),
                label: const Text('Use my current location'),
                onPressed: controller.useCurrentLocation,
              ),
            ),
          ),
        ),
      );
    }

    return FocusLanding(
      focusNode: _section,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _OriginLine extends StatelessWidget {
  const _OriginLine({required this.origin, this.announce = false});
  final Origin origin;

  /// Announce the line when it appears (a fix after "Try location again").
  final bool announce;

  @override
  Widget build(BuildContext context) {
    final line = Row(
      children: [
        // The icon alone shows GPS vs a searched place, as in maps apps.
        Icon(
          origin.provenance == OriginProvenance.gps
              ? Icons.my_location
              : Icons.place_outlined,
          size: 20,
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            'From: ${origin.label}',
            key: const Key('origin-line'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      ],
    );
    final detail = origin.detail;
    return Semantics(
      container: announce,
      liveRegion: announce,
      child: detail == null
          ? line
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                line,
                Text(detail, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
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
  const _FallbackActions({required this.reason, required this.onRetry});
  final LocationFailure reason;

  /// "Try location again": it turns the prompt into a spinner, so focus is
  /// handed on first (`_retryFromFallback`).
  final VoidCallback onRetry;

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
        TextButton(onPressed: onRetry, child: const Text('Try location again')),
      ],
    );
  }
}
