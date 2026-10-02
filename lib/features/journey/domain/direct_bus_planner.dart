import '../../../core/config/app_config.dart';
import '../../../core/geo/geo.dart';
import 'bus_network.dart';
import 'walking.dart';

/// Planner tunables. Defaults come from [JourneyConfig] (documented
/// assumptions in docs/assumptions.md); injectable for tests.
class PlannerConfig {
  const PlannerConfig({
    this.stopRadiusMeters = JourneyConfig.stopRadiusMeters,
    this.widenedStopRadiusMeters = JourneyConfig.widenedStopRadiusMeters,
    this.stopWeight = JourneyConfig.stopWeight,
    this.maxOptions = JourneyConfig.maxOptions,
    this.walkOnlyMaxMeters = JourneyConfig.walkOnlyMaxMeters,
  });

  final double stopRadiusMeters;
  final double widenedStopRadiusMeters;
  final double stopWeight;
  final int maxOptions;
  final double walkOnlyMaxMeters;
}

enum JourneyEnd { origin, destination }

/// The planner's answer. "No direct bus" and "no nearby stop" are ordinary
/// results (shown with the MRT alternative), not exceptions.
sealed class JourneyPlan {
  const JourneyPlan();
}

/// Origin and destination are close enough to walk (§9.2 item 9).
final class WalkOnly extends JourneyPlan {
  const WalkOnly(this.walk);
  final WalkEstimate walk;
}

/// One to [PlannerConfig.maxOptions] direct-bus options, best score first.
final class DirectBusOptions extends JourneyPlan {
  const DirectBusOptions(this.options, {required this.radiusMeters});
  final List<BusOption> options;

  /// The candidate radius that produced these options (400 or 800 m).
  final double radiusMeters;
}

/// No bus stop within the widened radius of [side].
final class NoNearbyStops extends JourneyPlan {
  const NoNearbyStops(this.side, {required this.radiusMeters});
  final JourneyEnd side;
  final double radiusMeters;
}

/// Stops exist near both ends, but no single service connects them in order.
final class NoDirectBus extends JourneyPlan {
  const NoDirectBus({required this.radiusMeters});
  final double radiusMeters;
}

/// A zero-transfer option: walk to [board], ride [stops] stops on [service]
/// in [direction], alight at [alight], walk to the destination.
class BusOption {
  const BusOption({
    required this.service,
    required this.direction,
    required this.board,
    required this.alight,
    required this.stops,
    required this.walkToStop,
    required this.walkFromStop,
    required this.score,
    required this.towardName,
    required this.isLoop,
  });

  final BusService service;

  /// Index into [BusService.directions].
  final int direction;
  final BusStop board;
  final BusStop alight;

  /// index(alight) − index(board) in that direction's ordered list.
  final int stops;
  final WalkEstimate walkToStop;
  final WalkEstimate walkFromStop;

  /// walkToStop + walkFromStop (min) + stopWeight × stops. Lower is better.
  final double score;

  /// Name of the last stop of this direction's list (§9.4), never guessed.
  final String towardName;

  /// The direction's list starts and ends at the same stop.
  final bool isLoop;

  @override
  String toString() =>
      'BusOption(${service.number} ${board.code}→${alight.code}, '
      '$stops stops, score $score)';
}

typedef _Candidate = ({BusStop stop, WalkEstimate walk});

/// Direct-bus (zero-transfer) planner (guide v2.1 §9.2–§9.4). Deterministic
/// and pure: no I/O and no live data.
///
/// 1. Within [PlannerConfig.walkOnlyMaxMeters] → [WalkOnly].
/// 2. Candidate stops within 400 m of each end (haversine). If that yields
///    no direct match (no candidates on a side, or no connecting service),
///    retry once at 800 m on both sides.
/// 3. For each service and direction, each origin-candidate occurrence `i` is
///    paired with the first occurrence `j > i` of each destination candidate
///    (`index(o) < index(d)`; never `d` before `o`; never `o == d`). Over all
///    occurrences the shortest segment is kept, which covers loops and
///    repeated stops (§9.4).
/// 4. Best option per service by (score, stops, direction, board code,
///    alight code); then the top [PlannerConfig.maxOptions] by (score,
///    stops, service number in natural order).
JourneyPlan planDirectBus(
  BusNetwork network,
  LatLng origin,
  LatLng destination, {
  PlannerConfig config = const PlannerConfig(),
}) {
  final direct = WalkEstimate.between(origin, destination);
  if (direct.straightLineMeters <= config.walkOnlyMaxMeters) {
    return WalkOnly(direct);
  }

  final first = _attempt(
    network,
    origin,
    destination,
    config.stopRadiusMeters,
    config,
  );
  if (first is DirectBusOptions) return first;
  return _attempt(
    network,
    origin,
    destination,
    config.widenedStopRadiusMeters,
    config,
  );
}

JourneyPlan _attempt(
  BusNetwork network,
  LatLng origin,
  LatLng destination,
  double radius,
  PlannerConfig config,
) {
  final fromOrigin = _candidates(network, origin, radius, towardStop: true);
  if (fromOrigin.isEmpty) {
    return NoNearbyStops(JourneyEnd.origin, radiusMeters: radius);
  }
  final toDestination = _candidates(
    network,
    destination,
    radius,
    towardStop: false,
  );
  if (toDestination.isEmpty) {
    return NoNearbyStops(JourneyEnd.destination, radiusMeters: radius);
  }

  final best = <BusOption>[];
  for (final service in network.services.values) {
    BusOption? serviceBest;
    for (var dir = 0; dir < service.directions.length; dir++) {
      final route = service.directions[dir];
      for (var i = 0; i < route.length; i++) {
        final o = fromOrigin[route[i]];
        if (o == null) continue;
        final seen = <String>{};
        for (var j = i + 1; j < route.length; j++) {
          final code = route[j];
          if (code == route[i] || !seen.add(code)) continue; // first after i
          final d = toDestination[code];
          if (d == null) continue;
          final option = _option(
            service,
            dir,
            route,
            o,
            d,
            j - i,
            network,
            config,
          );
          if (serviceBest == null || _perService(option, serviceBest) < 0) {
            serviceBest = option;
          }
        }
      }
    }
    if (serviceBest != null) best.add(serviceBest);
  }

  if (best.isEmpty) return NoDirectBus(radiusMeters: radius);
  best.sort(_overall);
  return DirectBusOptions(
    best.take(config.maxOptions).toList(),
    radiusMeters: radius,
  );
}

/// Stops within [radius] of [point], keyed by code.
Map<String, _Candidate> _candidates(
  BusNetwork network,
  LatLng point,
  double radius, {
  required bool towardStop,
}) => {
  for (final stop in network.stops.values)
    if (haversineMeters(point, stop.position) <= radius)
      stop.code: (
        stop: stop,
        walk: towardStop
            ? WalkEstimate.between(point, stop.position)
            : WalkEstimate.between(stop.position, point),
      ),
};

BusOption _option(
  BusService service,
  int direction,
  List<String> route,
  _Candidate o,
  _Candidate d,
  int stops,
  BusNetwork network,
  PlannerConfig config,
) {
  final last = route.last;
  return BusOption(
    service: service,
    direction: direction,
    board: o.stop,
    alight: d.stop,
    stops: stops,
    walkToStop: o.walk,
    walkFromStop: d.walk,
    score: o.walk.minutes + d.walk.minutes + config.stopWeight * stops,
    towardName: network.stops[last]?.name ?? last,
    isLoop: route.length > 1 && route.first == route.last,
  );
}

int _perService(BusOption a, BusOption b) {
  for (final c in [
    a.score.compareTo(b.score),
    a.stops.compareTo(b.stops),
    a.direction.compareTo(b.direction),
    a.board.code.compareTo(b.board.code),
    a.alight.code.compareTo(b.alight.code),
  ]) {
    if (c != 0) return c;
  }
  return 0;
}

int _overall(BusOption a, BusOption b) {
  for (final c in [
    a.score.compareTo(b.score),
    a.stops.compareTo(b.stops),
    compareServiceNumbers(a.service.number, b.service.number),
  ]) {
    if (c != 0) return c;
  }
  return 0;
}

final RegExp _serviceNumber = RegExp(r'^(\D*)(\d*)(.*)$');

/// Natural order for service numbers: `2` < `9A` < `10` < `10e` < `CT18`.
/// Compares the leading letters, then the number, then the suffix.
int compareServiceNumbers(String a, String b) {
  final ma = _serviceNumber.firstMatch(a)!;
  final mb = _serviceNumber.firstMatch(b)!;
  final prefix = ma.group(1)!.compareTo(mb.group(1)!);
  if (prefix != 0) return prefix;
  final na = int.tryParse(ma.group(2)!) ?? -1;
  final nb = int.tryParse(mb.group(2)!) ?? -1;
  if (na != nb) return na.compareTo(nb);
  final suffix = ma.group(3)!.compareTo(mb.group(3)!);
  return suffix != 0 ? suffix : a.compareTo(b);
}
