import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/errors/app_failure.dart';
import '../../core/http/json_http_client.dart';
import '../../core/time/clock.dart';
import 'data/nea_environment_repository.dart';
import 'domain/environment_models.dart';
import 'domain/environment_repository.dart';

final environmentRepositoryProvider = Provider<EnvironmentRepository>(
  (ref) => NeaEnvironmentRepository(
    ref.watch(jsonHttpClientProvider),
    ref.watch(clockProvider),
  ),
);

// One session-cached fetch per nationwide dataset (§15). They don't depend on
// location, so they start at launch (§5.1 step 2); the user's area/region is
// selected from them once an origin is known.

final forecastSnapshotProvider = FutureProvider<ForecastSnapshot>(
  (ref) => _typed(ref.watch(environmentRepositoryProvider).twoHourForecast),
);

final uvSnapshotProvider = FutureProvider<UvSnapshot>(
  (ref) => _typed(ref.watch(environmentRepositoryProvider).uv),
);

final pm25SnapshotProvider = FutureProvider<RegionalSnapshot>(
  (ref) => _typed(ref.watch(environmentRepositoryProvider).pm25OneHour),
);

final psiSnapshotProvider = FutureProvider<RegionalSnapshot>(
  (ref) => _typed(ref.watch(environmentRepositoryProvider).psiTwentyFourHour),
);

/// Guarantees `AsyncValue.error` is always an [AppFailure] (§12).
Future<T> _typed<T>(Future<T> Function() load) async {
  try {
    return await load();
  } on AppFailure {
    rethrow;
  } catch (e) {
    throw InvalidApiResponse('$e');
  }
}

/// Minimum refresh interval, injectable for tests.
final environmentRefreshIntervalProvider = Provider<Duration>(
  (ref) => AppTimings.minEnvironmentRefreshInterval,
);

final environmentRefresherProvider =
    NotifierProvider<EnvironmentRefresher, DateTime?>(EnvironmentRefresher.new);

/// Manual "refresh all" with a cooldown that debounces repeated taps. The
/// data.gov.sg limit (6 calls in any 10 s) is enforced separately, for every
/// caller, by `dataGovSgRateLimiterProvider` in the HTTP client: calls beyond
/// it wait for capacity instead of being sent.
/// State: when the last accepted refresh happened.
///
/// The cooldown only holds after a refresh that fully succeeded: if any
/// dataset is still loading, nothing new starts; if any failed, the refresh
/// may be repeated at once (as each tile's Retry can).
class EnvironmentRefresher extends Notifier<DateTime?> {
  @override
  DateTime? build() => null;

  List<AsyncValue<Object>> get _datasets => [
    ref.read(forecastSnapshotProvider),
    ref.read(uvSnapshotProvider),
    ref.read(pm25SnapshotProvider),
    ref.read(psiSnapshotProvider),
  ];

  RefreshAllResult refreshAll() {
    final datasets = _datasets;
    if (datasets.any((d) => d.isLoading)) {
      return RefreshAllResult.stillRefreshing;
    }
    final now = ref.read(clockProvider)();
    final last = state;
    if (last != null &&
        now.difference(last) < ref.read(environmentRefreshIntervalProvider) &&
        !datasets.any((d) => d.hasError)) {
      return RefreshAllResult.justUpdated;
    }
    state = now;
    ref
      ..invalidate(forecastSnapshotProvider)
      ..invalidate(uvSnapshotProvider)
      ..invalidate(pm25SnapshotProvider)
      ..invalidate(psiSnapshotProvider);
    return RefreshAllResult.started;
  }
}

/// Outcome of [EnvironmentRefresher.refreshAll].
enum RefreshAllResult {
  /// All four datasets are being fetched again.
  started,

  /// A fetch is still running; nothing new was started.
  stillRefreshing,

  /// Inside the cooldown after a refresh that fully succeeded.
  justUpdated,
}
