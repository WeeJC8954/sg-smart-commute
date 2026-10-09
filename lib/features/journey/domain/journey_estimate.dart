import '../../../core/config/app_config.dart';
import '../../../core/geo/geo.dart';
import 'bus_network.dart';
import 'direct_bus_planner.dart';

/// E2 static in-bus estimate for one bus ride (docs/assumptions.md,
/// "Estimated trip time (E2)"): the straight-line km between consecutive
/// stops of the ride × [minutesPerKm], plus [minutesPerStop] for each stop
/// travelled. A rough estimate from scheduled early and late trips, never an
/// ETA: it knows no waiting and no traffic.
///
/// [boardIndex] is the ride's occurrence in `service.directions[direction]`
/// and [stopCount] the stops travelled (alighting index − [boardIndex]), as
/// in [BusOption]; only that run of stops is summed, so loops and repeated
/// stops follow the planner's occurrence. Returns unrounded minutes, or null
/// when the ride is not in [network] as given, or the result is non-finite,
/// negative or over [JourneyConfig.busEstimateMaxMinutes] (omitted, never
/// clamped). The two rates are parameters only for tests.
double? estimateBusMinutes(
  BusNetwork network, {
  required BusService service,
  required int direction,
  required int boardIndex,
  required int stopCount,
  double minutesPerKm = JourneyConfig.busMinutesPerKm,
  double minutesPerStop = JourneyConfig.busMinutesPerStop,
}) {
  if (stopCount < 1 || boardIndex < 0) return null;
  if (direction < 0 || direction >= service.directions.length) return null;
  final codes = service.directions[direction];
  if (boardIndex + stopCount >= codes.length) return null;
  var meters = 0.0;
  LatLng? previous;
  for (var k = boardIndex; k <= boardIndex + stopCount; k++) {
    final position = network.stops[codes[k]]?.position;
    if (position == null) return null;
    if (previous != null) meters += haversineMeters(previous, position);
    previous = position;
  }
  final minutes = minutesPerKm * (meters / 1000) + minutesPerStop * stopCount;
  return minutes.isFinite &&
          minutes >= 0 &&
          minutes <= JourneyConfig.busEstimateMaxMinutes
      ? minutes
      : null;
}

/// The ride as shown: rounded up to a whole minute.
int rideMinutesShown(double busMinutes) => busMinutes.ceil();

/// Smallest multiple of [step] at or above [minutes] (both non-negative).
int roundUpToMultiple(int minutes, int step) =>
    (minutes + step - 1) ~/ step * step;

/// One direct option's estimated trip (E2), in whole minutes: the walks the
/// card already shows plus the ride rounded up. The total shown is the
/// smallest multiple of [JourneyConfig.estimateRoundingMinutes] at or above
/// those parts, which is also the exact sum rounded up, since the walks are
/// whole minutes.
class DirectJourneyEstimate {
  const DirectJourneyEstimate({
    required this.walkToStopMinutes,
    required this.rideMinutes,
    required this.walkFromStopMinutes,
  });

  final int walkToStopMinutes;
  final int rideMinutes;
  final int walkFromStopMinutes;

  int get partsMinutes => walkToStopMinutes + rideMinutes + walkFromStopMinutes;

  int get shownMinutes =>
      roundUpToMultiple(partsMinutes, JourneyConfig.estimateRoundingMinutes);
}

/// [option]'s estimated trip, or null when its ride cannot be estimated, or
/// its boarding and alighting stops are not where [network] has them (a
/// plan/network mismatch: no estimate, nothing else changes).
DirectJourneyEstimate? estimateDirectJourney(
  BusOption option,
  BusNetwork network,
) {
  final directions = option.service.directions;
  if (option.direction < 0 || option.direction >= directions.length) {
    return null;
  }
  final codes = directions[option.direction];
  final alightIndex = option.boardIndex + option.stops;
  if (option.boardIndex < 0 ||
      alightIndex >= codes.length ||
      codes[option.boardIndex] != option.board.code ||
      codes[alightIndex] != option.alight.code) {
    return null;
  }
  final ride = estimateBusMinutes(
    network,
    service: option.service,
    direction: option.direction,
    boardIndex: option.boardIndex,
    stopCount: option.stops,
  );
  if (ride == null) return null;
  return DirectJourneyEstimate(
    walkToStopMinutes: option.walkToStop.minutes,
    rideMinutes: rideMinutesShown(ride),
    walkFromStopMinutes: option.walkFromStop.minutes,
  );
}
