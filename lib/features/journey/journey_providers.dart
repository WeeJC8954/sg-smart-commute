import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/errors/failure_guard.dart';
import '../../core/geo/geo.dart';
import '../../core/http/json_http_client.dart';
import '../destination/domain/destination_controller.dart';
import '../origin/domain/origin_controller.dart';
import 'data/busrouter_repository.dart';
import 'data/mrt_asset_repository.dart';
import 'domain/bus_network.dart';
import 'domain/bus_network_repository.dart';
import 'domain/direct_bus_planner.dart';
import 'domain/mrt.dart';
import 'domain/option_selection.dart';
import 'domain/walking.dart';

/// Static bus data (busrouter). Overridden with a fake in tests.
final busNetworkRepositoryProvider = Provider<BusNetworkRepository>(
  (ref) => BusrouterRepository(ref.watch(jsonHttpClientProvider)),
);

/// The bus network, loaded on first use and then held for the session
/// (whatever the repository implementation). A failed load is held too: the
/// error stays until the user taps Retry on the journey card, which
/// invalidates this provider and loads again. Changing the origin or
/// destination re-plans against the held result and does not reload, so a
/// failure keeps showing the error (with Retry) rather than refetching the
/// same static data on every change.
final busNetworkProvider = FutureProvider<BusNetwork>(
  (ref) => guardAppFailure(
    ref.watch(busNetworkRepositoryProvider).load,
    context: 'bus network',
  ),
);

/// The bundled MRT station asset. Overridden with a fake in tests.
final mrtRepositoryProvider = Provider<MrtAssetRepository>(
  (ref) => MrtAssetRepository(),
);

/// Beyond this straight-line distance no MRT station is suggested (default:
/// JourneyConfig). The lookup and the "none within …" text both read it, so
/// they cannot disagree. Injectable for tests.
final mrtMaxDistanceMetersProvider = Provider<double>(
  (ref) => JourneyConfig.mrtMaxDistanceMeters,
);

/// Planner tunables (defaults: JourneyConfig). Injectable for tests.
final plannerConfigProvider = Provider<PlannerConfig>(
  (ref) => const PlannerConfig(),
);

LatLng? _origin(Ref ref) =>
    ref.watch(originControllerProvider.select((s) => s.origin?.position));

LatLng? _destination(Ref ref) =>
    ref.watch(destinationControllerProvider.select((s) => s.place?.position));

/// The direct-bus plan for the current origin and destination (guide v2.1
/// §9.2). Null until both exist. Recalculates when either changes. Bus data
/// is loaded on the first request that needs it (not for a walk-only
/// journey), once per session; a failure is `StaticDataUnavailable`.
final journeyPlanProvider = FutureProvider<JourneyPlan?>((ref) async {
  final origin = _origin(ref);
  final destination = _destination(ref);
  if (origin == null || destination == null) return null;
  final config = ref.watch(plannerConfigProvider);
  final direct = WalkEstimate.between(origin, destination);
  if (direct.straightLineMeters <= config.walkOnlyMaxMeters) {
    return WalkOnly(direct);
  }
  final network = await ref.watch(busNetworkProvider.future);
  return planDirectBus(network, origin, destination, config: config);
});

/// Which displayed direct-bus option the user selected (P2-M3). Journey state:
/// the journey card writes it and the map reads it. It never watches the
/// plan, so selecting never re-plans; it is tied to the plan object instead
/// ([selectedOptionIndex]), so it can never carry over to a new journey.
final optionSelectionProvider =
    NotifierProvider<OptionSelectionController, OptionSelection?>(
      OptionSelectionController.new,
    );

class OptionSelectionController extends Notifier<OptionSelection?> {
  @override
  OptionSelection? build() => null;

  /// Selects [plan]'s option at [index]; an index out of range is ignored.
  void select(DirectBusOptions plan, int index) {
    if (index < 0 || index >= plan.options.length) return;
    state = OptionSelection(plan, index);
  }
}

/// Nearest MRT station to the origin and to the destination (guide v2.1
/// §9.5, informational only). Null until both ends exist.
final mrtSuggestionProvider =
    FutureProvider<
      ({MrtSuggestion? nearOrigin, MrtSuggestion? nearDestination})?
    >((ref) async {
      final origin = _origin(ref);
      final destination = _destination(ref);
      if (origin == null || destination == null) return null;
      final maxMeters = ref.watch(mrtMaxDistanceMetersProvider);
      final stations = await guardAppFailure(
        ref.watch(mrtRepositoryProvider).stations,
        context: 'MRT stations',
      );
      return (
        nearOrigin: nearestMrtStation(stations, origin, maxMeters: maxMeters),
        nearDestination: nearestMrtStation(
          stations,
          destination,
          maxMeters: maxMeters,
        ),
      );
    });
