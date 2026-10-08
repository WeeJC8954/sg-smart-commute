import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/geo/geo.dart';
import '../../../core/time/clock.dart';
import '../../../core/ui/focus_landing.dart';
import '../../../core/ui/status_rows.dart';
import '../../origin/domain/origin.dart';
import '../../origin/domain/origin_controller.dart';
import '../domain/environment_locator.dart';
import '../domain/environment_models.dart';
import '../environment_providers.dart';
import 'reading_text.dart';

/// How many columns the Conditions tiles use at [width] (logical px) and
/// [textScale]: 4 in one row on wide screens, a 2 × 2 grid at normal phone
/// widths, and 1 column when two tiles would be narrower than
/// [HomeLayout.minTileWidth] × [textScale] (narrow screens or large text).
int conditionsColumns(double width, double textScale) {
  final scale = textScale < 1 ? 1.0 : textScale;
  const gap = HomeLayout.gridGap;
  if (width >= 4 * HomeLayout.minWideTileWidth * scale + 3 * gap) return 4;
  if (width >= 2 * HomeLayout.minTileWidth * scale + gap) return 2;
  return 1;
}

/// The four dashboard tiles (§6.1), as a responsive grid (see
/// [conditionsColumns]). Each tile loads and fails independently, so one
/// unavailable dataset never hides the others.
class EnvironmentDashboard extends ConsumerWidget {
  const EnvironmentDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position = ref.watch(
      originControllerProvider.select((s) => s.origin?.position),
    );
    ref.watch(uiTickProvider); // recompute ages, "Out of date", UV night
    final now = ref.watch(clockProvider)();

    final tiles = <Widget>[
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
          final night = isUvNight(now);
          final parts = ReadingText.uvParts(r.value);
          return _ReadingView(
            headline: night ? ReadingText.uv(r, now) : null,
            value: night ? null : parts.value,
            band: night ? null : parts.band,
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
          final parts = ReadingText.pm25Parts(r);
          return _ReadingView(
            value: parts.value,
            band: parts.band,
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
          final parts = ReadingText.psiParts(r);
          return _ReadingView(
            value: parts.value,
            band: parts.band,
            scope: ReadingText.scope(r),
            timestamp: ReadingText.timestamp(r.observedAt, now),
            stale: r.isStale(now),
          );
        },
      ),
    ];

    // Text scale as a factor (1.0 = default), for the column breakpoints.
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return LayoutBuilder(
      builder: (context, constraints) => _TileGrid(
        columns: conditionsColumns(constraints.maxWidth, textScale),
        tiles: tiles,
      ),
    );
  }
}

/// [tiles] in rows of [columns], in reading order. Tiles in a row share its
/// height, so the grid stays even whatever each tile's state.
class _TileGrid extends StatelessWidget {
  const _TileGrid({required this.columns, required this.tiles});

  final int columns;
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    const gap = HomeLayout.gridGap;
    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += columns) {
      final row = tiles.sublist(i, (i + columns).clamp(0, tiles.length));
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var c = 0; c < columns; c++) ...[
                if (c > 0) const SizedBox(width: gap),
                Expanded(
                  child: c < row.length ? row[c] : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return Column(
      key: Key('conditions-grid-$columns'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var r = 0; r < rows.length; r++) ...[
          if (r > 0) const SizedBox(height: gap),
          rows[r],
        ],
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

class _SnapshotTile<T> extends ConsumerStatefulWidget {
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
  ConsumerState<_SnapshotTile<T>> createState() => _SnapshotTileState<T>();
}

class _SnapshotTileState<T> extends ConsumerState<_SnapshotTile<T>> {
  /// Where a Retry leaves focus: the title, which stays (#56).
  final _title = FocusNode(debugLabel: 'tile-title');

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final _SnapshotTile<T>(:title, :provider, :needsPosition, :position) =
        widget;
    final value = ref.watch(provider);
    void retry() => ref.invalidate(provider);
    // Riverpod keeps the previous value when a refresh fails: that reading
    // stays on screen with its own timestamp, and the failure is shown under
    // it (docs/data-sources.md: "show the stale reading with its timestamp").
    final refreshFailed = value.hasError && !value.isLoading;
    final Widget body;
    if (value.isLoading && !value.hasValue) {
      body = BusyRow('Loading $title…');
    } else if (refreshFailed && !value.hasValue) {
      body = ErrorRetryRow(
        message: failureMessage(value.error),
        onRetry: retry,
        retryLabel: 'Retry $title',
        landing: _title,
      );
    } else if (needsPosition && position == null) {
      // "Waiting" only while the app waits for a fix (checking permission,
      // acquiring). At needsManual it has stopped waiting and asks for a
      // place, so say what the user can do. After a denial, location off, an
      // error or a fix outside SG nothing is pending; after an unanswered
      // prompt or a timeout a late fix may still fill the origin (late-fix
      // rule), and the tile then shows the reading.
      final needsManual = ref.watch(
        originControllerProvider.select(
          (s) => s.phase == OriginPhase.needsManual,
        ),
      );
      body = Text(
        needsManual ? ReadingText.needsOrigin : ReadingText.waitingForLocation,
      );
    } else if (refreshFailed) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _guardBuild(context, value.requireValue),
          ErrorRetryRow(
            key: const Key('refresh-failed'),
            message: "Couldn't refresh: ${failureMessage(value.error)}",
            liveRegion: true,
            onRetry: retry,
            retryLabel: 'Retry $title',
            landing: _title,
          ),
        ],
      );
    } else {
      body = _guardBuild(context, value.requireValue);
    }

    // Outlined: lighter than the elevated route and journey cards, since
    // Conditions are ambient information and the trip is the task.
    return Card.outlined(
      margin: EdgeInsets.zero, // spacing comes from the grid
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(widget.icon, size: 20),
                const SizedBox(width: 8),
                // Wraps in a narrow tile: "24-hr" / "1-hr" must stay visible.
                Flexible(
                  child: FocusLanding(
                    focusNode: _title,
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ),
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
      return widget.builder(snapshot, widget.position);
    } on AppFailure catch (f) {
      return ErrorRetryRow(message: f.message);
    }
  }
}

class _ReadingView extends StatelessWidget {
  const _ReadingView({
    required this.scope,
    required this.timestamp,
    required this.stale,
    this.value,
    this.band,
    this.headline,
    this.detail,
    this.icon,
  }) : assert((value == null) != (headline == null));

  /// The reading shown large ("54", "18 µg/m³", "7"); null when [headline]
  /// is used instead.
  final String? value;

  /// The official band of [value], shown as text (never colour alone, §7).
  final String? band;

  /// A sentence instead of a number: the forecast condition, or UV at night.
  final String? headline;
  final String scope;
  final String timestamp;
  final String? detail;
  final bool stale;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall;
    const tabular = [FontFeature.tabularFigures()];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (value != null)
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                value!,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontFeatures: tabular,
                ),
              ),
              if (band != null) _BandPill(band!),
            ],
          )
        else
          Row(
            children: [
              if (icon != null) ...[Icon(icon), const SizedBox(width: 8)],
              Flexible(
                child: Text(headline!, style: theme.textTheme.titleMedium),
              ),
            ],
          ),
        const SizedBox(height: 4),
        Text(scope),
        if (detail != null) Text(detail!, style: small),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(timestamp, style: small?.copyWith(fontFeatures: tabular)),
            // Text, not colour alone (§7, accessibility).
            if (stale)
              Text(
                ReadingText.staleLabel,
                style: small?.copyWith(
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

/// A band as a small pill. One neutral colour for every band: the word is
/// the meaning, so no colour scale implies thresholds NEA did not define.
class _BandPill extends StatelessWidget {
  const _BandPill(this.band);

  final String band;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(
          band,
          style: Theme.of(context).textTheme.labelLarge
              ?.copyWith(color: scheme.onSecondaryContainer),
        ),
      ),
    );
  }
}
