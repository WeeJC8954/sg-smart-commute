import '../../../core/config/app_config.dart';
import '../../../core/geo/geo.dart';

/// Estimated walk (guide v2.1 §9.3). There is no routing API in Phase 1, so
/// this is a straight-line distance with a detour factor, never a route:
///
///   walk_m   = haversine(a, b) × 1.3
///   walk_min = ceil(walk_m / 80)
///
/// It cannot see overhead bridges, barriers, expressways or rivers. Always
/// display it as `~N min walk (est.)` ([label]).
class WalkEstimate {
  const WalkEstimate._(this.straightLineMeters, this.walkMeters, this.minutes);

  factory WalkEstimate.between(
    LatLng a,
    LatLng b, {
    double detourFactor = JourneyConfig.walkDetourFactor,
    double metersPerMinute = JourneyConfig.walkMetersPerMinute,
  }) {
    final straight = haversineMeters(a, b);
    final walk = straight * detourFactor;
    return WalkEstimate._(straight, walk, (walk / metersPerMinute).ceil());
  }

  final double straightLineMeters;
  final double walkMeters;
  final int minutes;

  String get label => '~$minutes min walk (est.)';

  @override
  String toString() => 'WalkEstimate($minutes min, ${walkMeters.round()} m)';
}
