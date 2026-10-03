import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../destination/domain/destination_controller.dart';
import '../journey/journey_providers.dart';
import '../origin/domain/origin_controller.dart';
import 'domain/map_scene.dart';

/// What the journey map shows; null until both an origin and a destination
/// exist. It reads the plan the journey card already shows and never plans:
/// while that plan is being found or has failed, only the two ends are
/// marked, so a previous journey's stops are never shown on a new one.
final mapSceneProvider = Provider<MapScene?>((ref) {
  final origin = ref.watch(originControllerProvider.select((s) => s.origin));
  final destination = ref.watch(
    destinationControllerProvider.select((s) => s.place),
  );
  if (origin == null || destination == null) return null;
  final plan = ref.watch(journeyPlanProvider);
  return buildMapScene(
    origin: origin.position,
    originLabel: origin.label,
    destination: destination.position,
    destinationLabel: destination.displayName,
    plan: plan.isLoading || plan.hasError ? null : plan.value,
  );
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

  void show() => state = true;

  void hide() => state = false;
}
