import 'package:flutter_riverpod/flutter_riverpod.dart';

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
import 'domain/walking.dart';

/// Static bus data (busrouter). Overridden with a fake in tests.
final busNetworkRepositoryProvider = Provider<BusNetworkRepository>(
  (ref) => BusrouterRepository(ref.watch(jsonHttpClientProvider)),
);

/// The bus network, loaded on first use and then held for the session
/// (whatever the repository implementation). A failure is not held: Retry
/// invalidates this provider and loads again.
final busNetworkProvider = FutureProvider<BusNetwork>(
  (ref) => ref.watch(busNetworkRepositoryProvider).load(),
);

/// The bundled MRT station asset. Overridden with a fake in tests.
final mrtRepositoryProvider = Provider<MrtAssetRepository>(
  (ref) => MrtAssetRepository(),
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

/// Nearest MRT station to the origin and to the destination (guide v2.1
/// §9.5, informational only). Null until both ends exist.
final mrtSuggestionProvider =
    FutureProvider<
      ({MrtSuggestion? nearOrigin, MrtSuggestion? nearDestination})?
    >((ref) async {
      final origin = _origin(ref);
      final destination = _destination(ref);
      if (origin == null || destination == null) return null;
      final stations = await ref.watch(mrtRepositoryProvider).stations();
      return (
        nearOrigin: nearestMrtStation(stations, origin),
        nearDestination: nearestMrtStation(stations, destination),
      );
    });
