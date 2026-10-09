import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/errors/app_failure.dart';
import '../../core/http/json_http_client.dart';
import '../../core/time/clock.dart';
import '../journey/domain/direct_bus_planner.dart';
import '../journey/journey_providers.dart';
import 'data/arrivelah_bus_arrival_repository.dart';
import 'domain/bus_arrival.dart';
import 'domain/bus_arrival_cache.dart';
import 'domain/bus_arrival_repository.dart';

/// Live arrivals (ArriveLah). Overridden with a fake in tests.
final busArrivalRepositoryProvider = Provider<BusArrivalRepository>(
  (ref) => ArriveLahBusArrivalRepository(ref.watch(jsonHttpClientProvider)),
);

/// How long one stop's arrivals are reused (default:
/// [BusArrivalConfig.cacheTtl]). Injectable for tests.
final busArrivalCacheTtlProvider = Provider<Duration>(
  (ref) => BusArrivalConfig.cacheTtl,
);

/// The session's arrival cache: the only caller of the repository.
final busArrivalCacheProvider = Provider<BusArrivalCache>(
  (ref) => BusArrivalCache(
    ref.watch(busArrivalRepositoryProvider),
    ref.watch(clockProvider),
    ttl: ref.watch(busArrivalCacheTtlProvider),
  ),
);

/// One stop's outcome. A failed stop never hides another stop's arrivals,
/// and never removes the static route.
sealed class StopArrivalsResult {
  const StopArrivalsResult();
}

final class StopArrivalsLoaded extends StopArrivalsResult {
  const StopArrivalsLoaded(this.arrivals);
  final StopArrivals arrivals;
}

final class StopArrivalsFailed extends StopArrivalsResult {
  const StopArrivalsFailed(this.failure);
  final AppFailure failure;
}

/// Live arrivals for the boarding stops of one displayed [plan].
///
/// [plan] is the exact plan object they were fetched for. The UI shows them
/// only while that same plan is displayed, so a response that belongs to an
/// earlier journey can never be shown against a new one.
class JourneyArrivals {
  const JourneyArrivals({
    required this.plan,
    required this.checkedAt,
    required this.byStop,
  });

  final DirectBusOptions plan;

  /// When these arrivals were obtained (UTC). ETAs are counted from here.
  final DateTime checkedAt;
  final Map<String, StopArrivalsResult> byStop;
}

/// The one place that applies the "no stale attach" rule: arrivals are shown
/// only against the exact plan object they were fetched for.
extension ArrivalsForPlan on AsyncValue<JourneyArrivals?> {
  /// The current arrivals if they were fetched for [plan], else null (still
  /// loading, failed, or they belong to an earlier journey).
  JourneyArrivals? arrivalsFor(DirectBusOptions plan) {
    final arrivals = value;
    return arrivals != null && identical(arrivals.plan, plan) ? arrivals : null;
  }
}

/// Live arrivals for the displayed direct-bus options (guide v2.1 §9.2 step 7,
/// §10). Runs only after the static plan exists: no arrivals are requested
/// during the candidate search, nor for walk-only or no-bus results. Each
/// distinct boarding stop is requested once (via [BusArrivalCache]), however
/// many displayed services board there.
///
/// Manual refresh invalidates this provider only. The static plan is not
/// recomputed, and stops fetched within the cache TTL are not requested again.
final journeyArrivalsProvider = FutureProvider<JourneyArrivals?>((ref) async {
  // Read before the first await: a superseded build's ref is unmounted, and
  // reading it then throws (#72).
  final clock = ref.read(clockProvider);
  final plan = await ref.watch(journeyPlanProvider.future);
  if (plan is! DirectBusOptions) return null;
  final cache = ref.watch(busArrivalCacheProvider);
  final stops = {for (final o in plan.options) o.board.code}.toList();
  final results = await Future.wait([
    for (final stop in stops) _load(cache, stop),
  ]);
  return JourneyArrivals(
    plan: plan,
    checkedAt: clock(),
    byStop: {for (var i = 0; i < stops.length; i++) stops[i]: results[i]},
  );
});

Future<StopArrivalsResult> _load(BusArrivalCache cache, String stop) async {
  try {
    return StopArrivalsLoaded(await cache.arrivalsAt(stop));
  } on AppFailure catch (failure) {
    return StopArrivalsFailed(failure);
  }
}

/// Whether [option] boards a loop at the stop where its loop starts and ends
/// (see [nextArrivals]).
bool boardsAtLoopTerminal(BusOption option) =>
    option.isLoop &&
    option.service.directions[option.direction].first == option.board.code;
