import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/ui/focus_landing.dart';
import '../../../core/ui/section_heading.dart';
import '../../../core/ui/status_rows.dart';
import '../../bus_arrival/presentation/option_arrivals.dart';
import '../../destination/domain/destination_controller.dart';
import '../../origin/domain/origin_controller.dart';
import '../domain/direct_bus_planner.dart';
import '../domain/journey_estimate.dart';
import '../domain/mrt.dart';
import '../domain/option_selection.dart';
import '../journey_providers.dart';
import 'distance_text.dart';

/// The journey result (guide v2.1 §5.6, §9, §10): one "Suggested" direct bus
/// plus up to two alternatives, each with its live arrivals, or a clear
/// "no direct bus" / walk / unavailable state, and the MRT alternative. Live
/// arrivals are never invented, and their failure never hides the route.
///
/// With two or more options the user can select one (P2-M3): the selected
/// option is the one the journey map shows. Selecting never re-plans, never
/// reorders the options or moves "Suggested", and never touches arrivals.
///
/// A Retry or "Select" removes itself when pressed, so it leaves focus on
/// something that stays (#56): its section's heading, its option's "Take
/// Bus" line, or the new "Selected" mark.
class JourneyCard extends ConsumerStatefulWidget {
  const JourneyCard({super.key});

  static const String estimateNote =
      'Walking times are straight-line estimates, not routes.';

  /// E2 (docs/assumptions.md "Estimated trip time (E2)"): under
  /// [estimateNote] whenever at least one option shows an estimate.
  static const String tripEstimateNote =
      'Trip times are rough estimates based on scheduled early/late bus '
      'timings. They exclude waiting and live traffic conditions.';

  /// An option's estimated trip, below its live arrivals.
  static String tripLine(int minutes) => 'About $minutes min · excl. waiting';

  static String tripSemantics(int minutes) =>
      'Estimated trip, about $minutes minutes, not including waiting';

  /// The estimated ride, after the stop count on the bus step.
  static String rideDetail(int minutes) => '· ~$minutes min ride (est.)';

  static String rideSemantics(int stops, int minutes) =>
      '${_stopsText(stops)}, about $minutes '
      '${minutes == 1 ? 'minute' : 'minutes'} on the bus, estimated';

  @override
  ConsumerState<JourneyCard> createState() => _JourneyCardState();
}

class _JourneyCardState extends ConsumerState<JourneyCard> {
  final _heading = FocusNode(debugLabel: 'journey-heading');
  final _mrtHeading = FocusNode(debugLabel: 'mrt-heading');

  @override
  void dispose() {
    _heading.dispose();
    _mrtHeading.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
    final selection = ref.watch(optionSelectionProvider);
    // E2: estimates for a settled direct-bus plan only. The bus network is
    // read only then (already loaded for that plan), so a walk-only journey
    // never loads bus data. Display-only: the plan is never touched.
    final settled = plan.isLoading || plan.hasError ? null : plan.value;
    final network = settled is DirectBusOptions
        ? ref.watch(busNetworkProvider).value
        : null;
    final estimates = settled is DirectBusOptions && network != null
        ? [for (final o in settled.options) estimateDirectJourney(o, network)]
        : const <DirectJourneyEstimate?>[];

    return Card(
      key: const Key('journey-card'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeading(
              'Suggested journey',
              style: theme.textTheme.titleMedium,
              focusNode: _heading,
            ),
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
                retryLabel: 'Retry finding a bus',
                landing: _heading,
              ),
              AsyncValue(:final value) => _Plan(
                plan: value,
                estimates: estimates,
                selection: selection,
                onSelect: ref.read(optionSelectionProvider.notifier).select,
              ),
            },
            const Divider(height: 24),
            _Mrt(
              mrt: mrt,
              maxMeters: ref.watch(mrtMaxDistanceMetersProvider),
              onRetry: () => ref.invalidate(mrtSuggestionProvider),
              heading: _mrtHeading,
            ),
            const SizedBox(height: 8),
            Text(JourneyCard.estimateNote, style: theme.textTheme.bodySmall),
            if (estimates.any((e) => e != null)) ...[
              const SizedBox(height: 4),
              Text(
                JourneyCard.tripEstimateNote,
                key: const Key('trip-estimate-note'),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Plan extends StatelessWidget {
  const _Plan({
    required this.plan,
    required this.estimates,
    required this.selection,
    required this.onSelect,
  });
  final JourneyPlan? plan;

  /// E2: one estimate (or null) per option of a direct-bus [plan].
  final List<DirectJourneyEstimate?> estimates;

  /// The user's selection; it applies only to the plan it was made for.
  final OptionSelection? selection;
  final void Function(DirectBusOptions plan, int index) onSelect;

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
      final DirectBusOptions direct => _directOptions(theme, direct),
    };
  }

  Widget _directOptions(ThemeData theme, DirectBusOptions direct) {
    final shown = selectedOptionIndex(selection, direct);
    // Only a choice of two or more can be selected.
    VoidCallback? selectable(int i) =>
        direct.options.length > 1 ? () => onSelect(direct, i) : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Option(
          key: const Key('journey-suggested'),
          plan: direct,
          option: direct.options.first,
          estimate: estimates.elementAtOrNull(0),
          heading: 'Suggested',
          selected: shown == 0,
          onSelect: selectable(0),
        ),
        if (direct.options.length > 1) ...[
          const SizedBox(height: 12),
          SectionHeading('Alternatives', style: theme.textTheme.titleSmall),
          for (var i = 1; i < direct.options.length; i++)
            // Keyed by the option itself, so an open "Show steps" never
            // carries over to a different bus at the same position.
            KeyedSubtree(
              key: ValueKey(
                '${direct.options[i].board.code}-'
                '${direct.options[i].service.number}',
              ),
              child: _Option(
                key: Key('journey-alternative-$i'),
                plan: direct,
                option: direct.options[i],
                estimate: estimates.elementAtOrNull(i),
                collapsible: true,
                selected: shown == i,
                onSelect: selectable(i),
              ),
            ),
        ],
        const SizedBox(height: 8),
        ArrivalsFooter(plan: direct),
      ],
    );
  }
}

/// One direct-bus option: which bus and when (the summary) first, then the
/// steps in the order the rider does them. A [collapsible] option (an
/// alternative) starts with only its first step, the walk to its boarding
/// stop, so its live times always say which stop they are for; "Show steps"
/// reveals the rest.
class _Option extends StatefulWidget {
  const _Option({
    super.key,
    required this.plan,
    required this.option,
    this.estimate,
    this.heading,
    this.collapsible = false,
    this.selected = false,
    this.onSelect,
  });
  final DirectBusOptions plan;
  final BusOption option;

  /// E2: this option's estimated trip; null shows none.
  final DirectJourneyEstimate? estimate;
  final String? heading;
  final bool collapsible;

  /// This is the selected option (the one the map shows).
  final bool selected;

  /// Selects this option; null when there is nothing to choose between.
  final VoidCallback? onSelect;

  @override
  State<_Option> createState() => _OptionState();
}

class _OptionState extends State<_Option> {
  late bool _expanded = !widget.collapsible;

  /// Where a live-arrivals Retry leaves focus: the "Take Bus" line.
  final _title = FocusNode(debugLabel: 'option-title');

  /// The "Selected" mark, focused once "Select" has turned into it.
  final _mark = FocusNode(debugLabel: 'option-selected');

  /// Set by this option's own "Select": only then does the mark announce
  /// itself. A new plan's default selection is not something the user did,
  /// so it is not announced (#67).
  bool _userSelected = false;

  @override
  void didUpdateWidget(_Option oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.plan, widget.plan)) _userSelected = false;
  }

  @override
  void dispose() {
    _title.dispose();
    _mark.dispose();
    super.dispose();
  }

  void _select() {
    _userSelected = true;
    widget.onSelect!();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _mark.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final o = widget.option;
    final loop = o.isLoop ? ' (loop service)' : '';
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.heading != null) ...[
            Text(widget.heading!, style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ServiceBadge(o.service.number),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FocusLanding(
                      focusNode: _title,
                      child: Text(
                        'Take Bus ${o.service.number} toward '
                        '${o.towardName}$loop',
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    OptionArrivals(
                      key: Key('arrivals-${o.board.code}-${o.service.number}'),
                      plan: widget.plan,
                      option: o,
                      landing: _title,
                    ),
                    if (widget.estimate case final e?)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        // Its own node, read after the live arrivals, in
                        // words: never an ETA, never announced.
                        child: Semantics(
                          key: Key(
                            'trip-estimate-${o.board.code}-${o.service.number}',
                          ),
                          container: true,
                          label: JourneyCard.tripSemantics(e.shownMinutes),
                          excludeSemantics: true,
                          child: Text(
                            JourneyCard.tripLine(e.shownMinutes),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          _Steps(option: o, estimate: widget.estimate, full: _expanded),
          if (widget.onSelect != null || widget.collapsible)
            // Wraps below each other at large text or in a narrow card.
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (widget.onSelect != null)
                  _SelectControl(
                    service: o.service.number,
                    selected: widget.selected,
                    onSelect: _select,
                    markFocus: _mark,
                    announce: _userSelected,
                  ),
                if (widget.collapsible)
                  TextButton(
                    onPressed: () => setState(() => _expanded = !_expanded),
                    // Spoken with the bus: several alternatives each have one,
                    // and a bare "Show steps" doesn't say which it opens (#25).
                    child: Text(
                      _expanded ? 'Hide steps' : 'Show steps',
                      semanticsLabel:
                          '${_expanded ? 'Hide' : 'Show'} steps for Bus '
                          '${o.service.number}',
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// "Select" for an option that isn't selected, or the "Selected" mark (P2-M3).
/// Both are spoken with the bus, since every option has one.
class _SelectControl extends StatelessWidget {
  const _SelectControl({
    required this.service,
    required this.selected,
    required this.onSelect,
    required this.markFocus,
    required this.announce,
  });
  final String service;
  final bool selected;
  final VoidCallback onSelect;
  final FocusNode markFocus;

  /// The mark is a live region only after the user's own "Select".
  final bool announce;

  @override
  Widget build(BuildContext context) {
    if (!selected) {
      return OutlinedButton(
        key: Key('select-option-$service'),
        onPressed: onSelect,
        child: Text('Select', semanticsLabel: 'Select Bus $service'),
      );
    }
    final color = Theme.of(context).colorScheme.primary;
    return Semantics(
      key: Key('selected-option-$service'),
      // Its own node, so a screen reader stops on it. Selecting removes the
      // focused "Select" button: focus moves here, and the mark announces
      // itself (live region), but only then (#67).
      container: true,
      liveRegion: announce,
      selected: true,
      label: 'Bus $service selected',
      child: FocusLanding(
        focusNode: markFocus,
        child: ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, size: 18, color: color),
                const SizedBox(width: 4),
                Flexible(
                  child: Text('Selected', style: TextStyle(color: color)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The service number as a solid badge, the first thing the eye finds.
/// Decorative for screen readers: the line beside it says "Take Bus N".
class _ServiceBadge extends StatelessWidget {
  const _ServiceBadge(this.number);
  final String number;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: Container(
        constraints: const BoxConstraints(minWidth: 48),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: scheme.primary,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          number,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: scheme.onPrimary,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

/// Walk, ride, alight, walk: the rider's order (§5.6). Without [full], only
/// the walk to the boarding stop.
class _Steps extends StatelessWidget {
  const _Steps({required this.option, required this.full, this.estimate});
  final BusOption option;
  final bool full;

  /// E2: adds the estimated ride to the bus step.
  final DirectJourneyEstimate? estimate;

  @override
  Widget build(BuildContext context) {
    final o = option;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Step(
            Icons.directions_walk,
            '${o.walkToStop.label} to Bus Stop ${o.board.code} — '
            '${o.board.name}',
          ),
          if (full) ...[
            if (estimate case final e?)
              _Step(
                Icons.directions_bus_outlined,
                _stopsText(o.stops),
                key: Key('ride-step-${o.board.code}-${o.service.number}'),
                detail: JourneyCard.rideDetail(e.rideMinutes),
                semanticsLabel: JourneyCard.rideSemantics(
                  o.stops,
                  e.rideMinutes,
                ),
              )
            else
              _Step(Icons.directions_bus_outlined, _stopsText(o.stops)),
            _Step(
              Icons.place_outlined,
              'Alight at ${o.alight.code} — ${o.alight.name}',
            ),
            _Step(
              Icons.directions_walk,
              '${o.walkFromStop.label} to destination',
            ),
          ],
        ],
      ),
    );
  }
}

String _stopsText(int stops) => '$stops ${stops == 1 ? 'stop' : 'stops'}';

class _Step extends StatelessWidget {
  const _Step(
    this.icon,
    this.text, {
    super.key,
    this.detail,
    this.semanticsLabel,
  });
  final IconData icon;
  final String text;

  /// E2: the estimated ride, after [text] on the same line. Two texts, so the
  /// stop count stays exactly as without an estimate; they wrap at large
  /// text.
  final String? detail;

  /// Read instead of the visible texts, as one node.
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final extra = detail;
    final step = Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: extra == null
                ? Text(text)
                : Wrap(spacing: 4, children: [Text(text), Text(extra)]),
          ),
        ],
      ),
    );
    final label = semanticsLabel;
    return label == null
        ? step
        : Semantics(
            container: true,
            label: label,
            excludeSemantics: true,
            child: step,
          );
  }
}

class _Mrt extends StatelessWidget {
  const _Mrt({
    required this.mrt,
    required this.maxMeters,
    required this.onRetry,
    required this.heading,
  });
  final AsyncValue<
    ({MrtSuggestion? nearOrigin, MrtSuggestion? nearDestination})?
  >
  mrt;

  /// The radius the lookup used, for the "none within …" text.
  final double maxMeters;
  final VoidCallback onRetry;

  /// The heading's focus node: where Retry leaves focus.
  final FocusNode heading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const Key('journey-mrt'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading(
          'MRT alternative',
          style: theme.textTheme.titleSmall,
          focusNode: heading,
        ),
        switch (mrt) {
          AsyncValue(isLoading: true) => const BusyRow(
            'Finding the nearest MRT…',
          ),
          AsyncValue(:final error?, isLoading: false) => ErrorRetryRow(
            message: failureMessage(error),
            onRetry: onRetry,
            retryLabel: 'Retry finding the nearest MRT',
            landing: heading,
          ),
          AsyncValue(:final value) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _line(MrtWording.nearOrigin, value?.nearOrigin),
                key: const Key('journey-mrt-origin'),
              ),
              Text(
                _line(MrtWording.nearDestination, value?.nearDestination),
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
      : '${MrtWording.named(label, s.station)} — ${s.walk.label}';
}
