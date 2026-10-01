import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/geo/geo.dart';
import '../../../core/time/clock.dart';
import '../../origin/domain/origin_controller.dart';
import '../domain/environment_locator.dart';
import '../domain/environment_models.dart';
import '../environment_providers.dart';
import 'reading_text.dart';

/// The four dashboard tiles (§6.1). Each tile loads and fails independently,
/// so one unavailable dataset never hides the others.
class EnvironmentDashboard extends ConsumerWidget {
  const EnvironmentDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position = ref.watch(
      originControllerProvider.select((s) => s.origin?.position),
    );
    final now = ref.watch(clockProvider)();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SnapshotTile<ForecastSnapshot>(
          key: const Key('tile-forecast'),
          title: ReadingText.forecastTitle,
          icon: Icons.cloud_outlined,
          provider: forecastSnapshotProvider,
          needsPosition: true,
          position: position,
          builder: (s, p) {
            final r = EnvironmentLocator.forecast(s, p!);
            return _ReadingView(
              icon: forecastIcon(r.value),
              headline: ReadingText.forecast(r),
              scope: ReadingText.scope(r),
              detail: s.validText.isEmpty ? null : 'Valid ${s.validText}',
              timestamp: ReadingText.timestamp(r.observedAt, now),
              stale: r.isStale(now),
            );
          },
        ),
        _SnapshotTile<UvSnapshot>(
          key: const Key('tile-uv'),
          title: ReadingText.uvTitle,
          icon: Icons.wb_sunny_outlined,
          provider: uvSnapshotProvider,
          needsPosition: false,
          position: position,
          builder: (s, _) {
            final r = EnvironmentLocator.uv(s);
            return _ReadingView(
              headline: ReadingText.uv(r, now),
              scope: ReadingText.scope(r),
              detail: ReadingText.uvNightDetail(r, now),
              timestamp: ReadingText.timestamp(r.observedAt, now),
              stale: r.isStale(now),
            );
          },
        ),
        _SnapshotTile<RegionalSnapshot>(
          key: const Key('tile-pm25'),
          title: ReadingText.pm25Title,
          icon: Icons.grain,
          provider: pm25SnapshotProvider,
          needsPosition: true,
          position: position,
          builder: (s, p) {
            final r = EnvironmentLocator.regional(s, p!);
            return _ReadingView(
              headline: ReadingText.pm25(r),
              scope: ReadingText.scope(r),
              timestamp: ReadingText.timestamp(r.observedAt, now),
              stale: r.isStale(now),
            );
          },
        ),
        _SnapshotTile<RegionalSnapshot>(
          key: const Key('tile-psi'),
          title: ReadingText.psiTitle,
          icon: Icons.masks_outlined,
          provider: psiSnapshotProvider,
          needsPosition: true,
          position: position,
          builder: (s, p) {
            final r = EnvironmentLocator.regional(s, p!);
            return _ReadingView(
              headline: ReadingText.psi(r),
              scope: ReadingText.scope(r),
              timestamp: ReadingText.timestamp(r.observedAt, now),
              stale: r.isStale(now),
            );
          },
        ),
      ],
    );
  }
}

IconData forecastIcon(String? condition) {
  final c = (condition ?? '').toLowerCase();
  if (c.contains('thunder')) return Icons.thunderstorm_outlined;
  if (c.contains('rain') || c.contains('shower')) return Icons.umbrella;
  if (c.contains('night')) return Icons.nightlight_outlined;
  if (c.contains('fair') || c.contains('sunny')) return Icons.wb_sunny_outlined;
  if (c.contains('haz') || c.contains('mist') || c.contains('fog')) {
    return Icons.blur_on;
  }
  if (c.contains('wind')) return Icons.air;
  return Icons.cloud_outlined;
}

class _SnapshotTile<T> extends ConsumerWidget {
  const _SnapshotTile({
    super.key,
    required this.title,
    required this.icon,
    required this.provider,
    required this.needsPosition,
    required this.position,
    required this.builder,
  });

  final String title;
  final IconData icon;
  final FutureProvider<T> provider;
  final bool needsPosition;
  final LatLng? position;
  final Widget Function(T snapshot, LatLng? position) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(provider);
    final Widget body;
    if (value.isLoading && !value.hasValue) {
      body = _Loading(label: 'Loading $title…');
    } else if (value.hasError && !value.isLoading) {
      body = _ErrorView(
        failure: value.error,
        onRetry: () => ref.invalidate(provider),
      );
    } else if (needsPosition && position == null) {
      body = const Text('Waiting for your location');
    } else {
      body = _guardBuild(context, value.requireValue);
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: 8),
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                if (value.isLoading && value.hasValue) ...[
                  const SizedBox(width: 8),
                  const SizedBox.square(
                    dimension: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            body,
          ],
        ),
      ),
    );
  }

  Widget _guardBuild(BuildContext context, T snapshot) {
    try {
      return builder(snapshot, position);
    } on AppFailure catch (f) {
      return _ErrorView(failure: f, onRetry: null);
    }
  }
}

class _ReadingView extends StatelessWidget {
  const _ReadingView({
    required this.headline,
    required this.scope,
    required this.timestamp,
    required this.stale,
    this.detail,
    this.icon,
  });

  final String headline;
  final String scope;
  final String timestamp;
  final String? detail;
  final bool stale;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (icon != null) ...[Icon(icon), const SizedBox(width: 8)],
            Flexible(child: Text(headline, style: theme.textTheme.titleMedium)),
          ],
        ),
        Text(scope),
        if (detail != null) Text(detail!),
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(timestamp, style: theme.textTheme.bodySmall),
            // Text, not colour alone (§7, accessibility).
            if (stale)
              Text(
                'Stale',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading({required this.label});
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

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.failure, required this.onRetry});
  final Object? failure;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final message = failure is AppFailure
        ? (failure as AppFailure).message
        : 'Something went wrong.';
    return Row(
      children: [
        Expanded(child: Text(message)),
        if (onRetry != null)
          TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    );
  }
}
