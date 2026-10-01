import '../../../core/config/app_config.dart';
import '../../../core/geo/geo.dart';
import 'walking.dart';

/// One exit of an MRT/LRT station (LTA MRT Station Exit dataset).
class MrtExit {
  const MrtExit({required this.code, required this.position});

  /// As published, e.g. `Exit A`, `Exit 1`.
  final String code;
  final LatLng position;
}

/// An MRT/LRT station: its verified exits grouped under one name. Phase 1 is
/// informational only (guide v2.1 §9.5): name and estimated walk; no codes,
/// lines, routing or arrivals.
class MrtStation {
  const MrtStation({required this.name, required this.exits});

  final String name;
  final List<MrtExit> exits;

  @override
  String toString() => 'MrtStation($name, ${exits.length} exits)';
}

class MrtSuggestion {
  const MrtSuggestion({
    required this.station,
    required this.nearestExit,
    required this.walk,
  });

  final MrtStation station;
  final MrtExit nearestExit;
  final WalkEstimate walk;
}

/// The station whose **nearest exit** is closest to [point] (not a centroid:
/// one station's exits can be ~600 m apart). Ties go to the name in
/// alphabetical order. Null when no exit is within [maxMeters].
MrtSuggestion? nearestMrtStation(
  List<MrtStation> stations,
  LatLng point, {
  double maxMeters = JourneyConfig.mrtMaxDistanceMeters,
}) {
  MrtSuggestion? best;
  for (final station in stations) {
    for (final exit in station.exits) {
      final walk = WalkEstimate.between(point, exit.position);
      if (walk.straightLineMeters > maxMeters) continue;
      final current = best;
      if (current == null ||
          walk.straightLineMeters < current.walk.straightLineMeters ||
          (walk.straightLineMeters == current.walk.straightLineMeters &&
              station.name.compareTo(current.station.name) < 0)) {
        best = MrtSuggestion(station: station, nearestExit: exit, walk: walk);
      }
    }
  }
  return best;
}
