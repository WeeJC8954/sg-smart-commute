import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/failure_guard.dart';
import '../../core/http/json_http_client.dart';
import '../destination/domain/destination_controller.dart';
import '../journey/domain/direct_bus_planner.dart';
import '../journey/journey_providers.dart';
import '../origin/domain/origin_controller.dart';
import 'data/busrouter_route_geometry_repository.dart';
import 'domain/map_scene.dart';
import 'domain/ride_geometry.dart';
import 'domain/route_geometry.dart';

/// What the journey map shows; null until both an origin and a destination
/// exist. It reads the plan the journey card already shows and never plans:
/// while that plan is being found or has failed, only the two ends are
/// marked, so a previous journey's stops are never shown on a new one. The
/// bus stop table is read only for a direct-bus plan, so a walk-only journey
/// never touches bus data.
final mapSceneProvider = Provider<MapScene?>((ref) {
  final origin = ref.watch(originControllerProvider.select((s) => s.origin));
  final destination = ref.watch(
    destinationControllerProvider.select((s) => s.place),
  );
  if (origin == null || destination == null) return null;
  final plan = ref.watch(journeyPlanProvider);
  final current = plan.isLoading || plan.hasError ? null : plan.value;
  final stops = current is DirectBusOptions
      ? ref.watch(busNetworkProvider).value?.stops
      : null;
  return buildMapScene(
    origin: origin.position,
    originLabel: origin.label,
    destination: destination.position,
    destinationLabel: destination.displayName,
    plan: current,
    stops: stops,
  );
});

/// busrouter routes.min.json. Overridden with a fake in tests.
final routeGeometryRepositoryProvider = Provider<RouteGeometryRepository>(
  (ref) => BusrouterRouteGeometryRepository(ref.watch(jsonHttpClientProvider)),
);

/// busrouter routes.min.json, loaded the first time an open map shows a
/// direct-bus journey and then held for the session. A failure is held too,
/// with no automatic retry; the next "Show map" tries again
/// ([MapExpanded.show]).
final routeGeometryProvider = FutureProvider<RouteGeometry>(
  (ref) => guardAppFailure(
    ref.watch(routeGeometryRepositoryProvider).load,
    context: 'bus route geometry',
  ),
);

/// The current scene's ride line; null when the scene has no ride. Watched
/// only by the open map, so nothing is fetched before "Show map". Derived
/// from the current scene, so it can never belong to an earlier journey.
/// Auto-disposed: once the map is hidden it stops watching
/// [routeGeometryProvider] (which stays alive for the session), so a hidden
/// map never rebuilds this and never starts a load.
final rideLineProvider = Provider.autoDispose<AsyncValue<RideLine>?>((ref) {
  final ride = ref.watch(mapSceneProvider.select((s) => s?.ride));
  if (ride == null) return null;
  return ref
      .watch(routeGeometryProvider)
      .whenData((geometry) => matchRide(ride, geometry));
});

/// Whether the user opened the map. Session UI state only, not part of the
/// journey: the map starts closed, so no tile is requested until the user
/// asks for it (docs/map-feasibility.md §4.2, rule 1), and it stays open
/// across journeys until the user hides it.
final mapExpandedProvider = NotifierProvider<MapExpanded, bool>(
  MapExpanded.new,
);

class MapExpanded extends Notifier<bool> {
  @override
  bool build() => false;

  void show() {
    // Reopening the map is the user's retry for a failed route-line load, but
    // only for a journey that has a bus ride: the open map then watches the
    // load at once. For a walk-only or no-bus journey nothing watches it, and
    // an invalidated provider would start its load on the next read, so it is
    // left untouched. Only a provider that already exists is looked at, and a
    // retry already under way (error while loading) is not restarted.
    if (ref.read(mapSceneProvider)?.ride != null &&
        ref.exists(routeGeometryProvider)) {
      final geometry = ref.read(routeGeometryProvider);
      if (geometry.hasError && !geometry.isLoading) {
        ref.invalidate(routeGeometryProvider);
      }
    }
    state = true;
  }

  void hide() => state = false;
}
