import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/time/clock.dart';
import '../../../core/time/sgt_format.dart';
import '../../../core/ui/status_rows.dart';
import '../../journey/domain/direct_bus_planner.dart';
import '../bus_arrival_providers.dart';
import '../domain/bus_arrival.dart';

/// Live arrivals under one direct-bus option (guide v2.1 §10): up to three
/// ETAs ("Arr", "N min"), optional details of the next bus, or a clear
/// unavailable state with Retry. The static option above it always stays.
class OptionArrivals extends ConsumerWidget {
  const OptionArrivals({
    super.key,
    required this.plan,
    required this.option,
    this.landing,
  });

  /// The plan currently displayed. Arrivals fetched for any other plan are
  /// never shown here.
  final DirectBusOptions plan;
  final BusOption option;

  /// Where Retry leaves focus (see [ErrorRetryRow.landing]).
  final FocusNode? landing;

  static const String noArrival = 'No live arrival available';
  static const String checking = 'Checking live arrivals…';
  static final String outdated =
      'Times checked over ${BusArrivalConfig.outdatedAfter.inMinutes} min ago. '
      'Refresh arrivals for current times.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(journeyArrivalsProvider);
    final current = async.arrivalsFor(plan);
    final theme = Theme.of(context);
    ref.watch(uiTickProvider); // ETAs count down between checks
    final now = ref.watch(clockProvider)();

    if (current == null) {
      if (async case AsyncValue(:final error?, isLoading: false)) {
        return _ArrivalFailed(
          error: error,
          service: option.service.number,
          landing: landing,
          announce: identical(option, plan.options.first),
        );
      }
      return const _Checking();
    }
    return switch (current.byStop[option.board.code]) {
      null => const _Checking(),
      StopArrivalsFailed(:final failure) => _ArrivalFailed(
        error: failure,
        service: option.service.number,
        landing: landing,
        announce: identical(
          option,
          plan.options.firstWhere(
            (o) => current.byStop[o.board.code] is StopArrivalsFailed,
          ),
        ),
      ),
      StopArrivalsLoaded(:final arrivals) => _loaded(
        theme,
        arrivals,
        now,
        current.checkedAt,
      ),
    };
  }

  /// ETAs are counted from [now] (the clock, re-read every UI tick), so they
  /// count down between checks; past [BusArrivalConfig.outdatedAfter] since
  /// [checkedAt] they are replaced by a prompt to refresh.
  Widget _loaded(
    ThemeData theme,
    StopArrivals arrivals,
    DateTime now,
    DateTime checkedAt,
  ) {
    if (now.difference(checkedAt) > BusArrivalConfig.outdatedAfter) {
      return Text(outdated, style: theme.textTheme.bodyMedium);
    }
    final next = nextArrivals(
      arrivals,
      option.service.number,
      now: now,
      boardsAtLoopTerminal: boardsAtLoopTerminal(option),
    );
    if (next.isEmpty) return Text(noArrival, style: theme.textTheme.bodyMedium);
    final details = _details(next.first);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Next buses: ${next.map((a) => _eta(a, now)).join(' · ')}',
          semanticsLabel:
              'Next buses: '
              '${next.map((a) => _spokenEta(a, now)).join(', ')}',
          // The emphasis of the option, with digits that don't shift as the
          // times count down.
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        if (details.isNotEmpty)
          Text(
            'Next bus: ${details.join(' · ')}',
            style: theme.textTheme.bodySmall,
          ),
      ],
    );
  }

  static String _eta(BusArrival a, DateTime now) {
    final label = etaLabel(a.estimatedArrival!, now);
    return a.monitored == false ? '$label (scheduled)' : label;
  }

  static String _spokenEta(BusArrival a, DateTime now) {
    final spoken = etaSpoken(a.estimatedArrival!, now);
    return a.monitored == false ? '$spoken, scheduled' : spoken;
  }

  /// Secondary details of the next bus, only those the provider sent. Load is
  /// words, never colour alone.
  static List<String> _details(BusArrival a) => [
    if (a.load != null) a.load!.label,
    if (a.wheelchairAccessible == true) 'Wheelchair accessible',
    if (a.type != null) a.type!.label,
  ];
}

/// Source, check time and the manual refresh (guide v2.1 §10: a refresh
/// button is required; arrivals are reused for [BusArrivalConfig.cacheTtl];
/// no automatic polling).
class ArrivalsFooter extends ConsumerWidget {
  const ArrivalsFooter({super.key, required this.plan});
  final DirectBusOptions plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(journeyArrivalsProvider);
    final current = async.arrivalsFor(plan);
    final theme = Theme.of(context);
    final checked = current == null
        ? ''
        : ' · checked ${formatSgtTime(current.checkedAt)} SGT';
    final attribution = Text(
      '$arriveLahAttribution$checked',
      key: const Key('arrivals-footer'),
      style: theme.textTheme.bodySmall,
    );
    final refreshing = async.isLoading && current != null;
    const spinner = Padding(
      padding: EdgeInsets.only(right: 8),
      child: SizedBox.square(
        dimension: 14,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          semanticsLabel: 'Refreshing arrivals',
        ),
      ),
    );
    final refresh = TextButton.icon(
      key: const Key('arrivals-refresh'),
      onPressed: () => ref.invalidate(journeyArrivalsProvider),
      icon: const Icon(Icons.refresh, size: 18),
      label: const Text('Refresh arrivals'),
    );
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >=
            HomeLayout.arrivalsFooterMinRowWidth * textScale) {
          return Row(
            children: [
              Expanded(child: attribution),
              if (refreshing) spinner,
              refresh,
            ],
          );
        }
        // Large text or a narrow card: the button goes below, and its label
        // may wrap rather than overflow.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            attribution,
            Row(
              children: [
                if (refreshing) spinner,
                Flexible(child: refresh),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _Checking extends StatelessWidget {
  const _Checking();

  @override
  Widget build(BuildContext context) =>
      const BusyRow(OptionArrivals.checking, compact: true);
}

class _ArrivalFailed extends ConsumerWidget {
  const _ArrivalFailed({
    required this.error,
    required this.service,
    required this.landing,
    required this.announce,
  });
  final Object error;

  /// The bus this row is under: each option can show its own Retry.
  final String service;
  final FocusNode? landing;

  /// A failure arrives away from focus (after a refresh or a new journey), so
  /// it is announced, but only on the first failed option: a failure several
  /// options share is heard once (#66).
  final bool announce;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ErrorRetryRow(
    message: 'Live arrivals: ${failureMessage(error)}',
    onRetry: () => ref.invalidate(journeyArrivalsProvider),
    retryLabel: 'Retry live arrivals for Bus $service',
    landing: landing,
    liveRegion: announce,
  );
}
