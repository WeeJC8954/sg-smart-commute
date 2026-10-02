import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/ui/status_rows.dart';
import '../../bus_arrival/presentation/option_arrivals.dart';
import '../../destination/domain/destination_controller.dart';
import '../../origin/domain/origin_controller.dart';
import '../domain/direct_bus_planner.dart';
import '../domain/mrt.dart';
import '../journey_providers.dart';
import 'distance_text.dart';

/// The journey result (guide v2.1 §5.6, §9, §10): one "Suggested" direct bus
/// plus up to two alternatives, each with its live arrivals, or a clear
/// "no direct bus" / walk / unavailable state, and the MRT alternative. Live
/// arrivals are never invented, and their failure never hides the route.
class JourneyCard extends ConsumerWidget {
  const JourneyCard({super.key});

  static const String estimateNote =
      'Walking times are straight-line estimates, not routes.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ready = ref.watch(
      originControllerProvider.select((s) => s.origin != null),
    );
    final hasDestination = ref.watch(
      destinationControllerProvider.select((s) => s.place != null),
    );
    if (!ready || !hasDestination) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final plan = ref.watch(journeyPlanProvider);
    final mrt = ref.watch(mrtSuggestionProvider);

    return Card(
      key: const Key('journey-card'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Suggested journey', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            switch (plan) {
              AsyncValue(isLoading: true) => const BusyRow(
                'Finding a direct bus…',
              ),
              AsyncValue(:final error?, isLoading: false) => ErrorRetryRow(
                message: failureMessage(error),
                onRetry: () => ref
                  ..invalidate(busNetworkProvider)
                  ..invalidate(journeyPlanProvider),
              ),
              AsyncValue(:final value) => _Plan(plan: value),
            },
            const Divider(height: 24),
            _Mrt(
              mrt: mrt,
              maxMeters: ref.watch(mrtMaxDistanceMetersProvider),
              onRetry: () => ref.invalidate(mrtSuggestionProvider),
            ),
            const SizedBox(height: 8),
            Text(estimateNote, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _Plan extends StatelessWidget {
  const _Plan({required this.plan});
  final JourneyPlan? plan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return switch (plan) {
      null => const SizedBox.shrink(),
      WalkOnly(:final walk) => Text(
        'Your destination is close: ${walk.label} '
        '(about ${walk.straightLineMeters.round()} m in a straight line).',
        key: const Key('journey-walk-only'),
      ),
      NoNearbyStops(:final side, :final radiusMeters) => Text(
        'No bus stop within ${radiusMeters.round()} m of your '
        '${side == JourneyEnd.origin ? 'starting point' : 'destination'}.',
        key: const Key('journey-no-stops'),
      ),
      NoDirectBus(:final radiusMeters) => Column(
        key: const Key('journey-no-direct'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('No direct bus found', style: theme.textTheme.titleSmall),
          Text(
            'No single bus connects stops within ${radiusMeters.round()} m '
            'of both ends. See the MRT option below.',
          ),
        ],
      ),
      final DirectBusOptions direct => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Option(
            key: const Key('journey-suggested'),
            plan: direct,
            option: direct.options.first,
            heading: 'Suggested',
          ),
          if (direct.options.length > 1) ...[
            const SizedBox(height: 12),
            Text('Alternatives', style: theme.textTheme.titleSmall),
            for (var i = 1; i < direct.options.length; i++)
              _Option(
                key: Key('journey-alternative-$i'),
                plan: direct,
                option: direct.options[i],
              ),
          ],
          const SizedBox(height: 8),
          ArrivalsFooter(plan: direct),
        ],
      ),
    };
  }
}

/// One direct-bus option, in the order the rider does it.
class _Option extends StatelessWidget {
  const _Option({
    super.key,
    required this.plan,
    required this.option,
    this.heading,
  });
  final DirectBusOptions plan;
  final BusOption option;
  final String? heading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final o = option;
    final loop = o.isLoop ? ' (loop service)' : '';
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (heading != null)
            Text(heading!, style: theme.textTheme.labelLarge),
          Text(
            '${o.walkToStop.label} to Bus Stop ${o.board.code} — ${o.board.name}',
          ),
          Text(
            'Take Bus ${o.service.number} toward ${o.towardName}$loop',
            style: theme.textTheme.titleSmall,
          ),
          OptionArrivals(
            key: Key('arrivals-${o.board.code}-${o.service.number}'),
            plan: plan,
            option: o,
          ),
          Text('${o.stops} ${o.stops == 1 ? 'stop' : 'stops'}'),
          Text('Alight at ${o.alight.code} — ${o.alight.name}'),
          Text('${o.walkFromStop.label} to destination'),
        ],
      ),
    );
  }
}

class _Mrt extends StatelessWidget {
  const _Mrt({
    required this.mrt,
    required this.maxMeters,
    required this.onRetry,
  });
  final AsyncValue<
    ({MrtSuggestion? nearOrigin, MrtSuggestion? nearDestination})?
  >
  mrt;

  /// The radius the lookup used, for the "none within …" text.
  final double maxMeters;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const Key('journey-mrt'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('MRT alternative', style: theme.textTheme.titleSmall),
        switch (mrt) {
          AsyncValue(isLoading: true) => const BusyRow(
            'Finding the nearest MRT…',
          ),
          AsyncValue(:final error?, isLoading: false) => ErrorRetryRow(
            message: failureMessage(error),
            onRetry: onRetry,
          ),
          AsyncValue(:final value) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _line('Nearest MRT', value?.nearOrigin),
                key: const Key('journey-mrt-origin'),
              ),
              Text(
                _line('Near your destination', value?.nearDestination),
                key: const Key('journey-mrt-destination'),
              ),
            ],
          ),
        },
      ],
    );
  }

  String _line(String label, MrtSuggestion? s) => s == null
      ? '$label: none within about ${distanceText(maxMeters)}'
      : '$label: ${s.station.name} — ${s.walk.label}';
}
