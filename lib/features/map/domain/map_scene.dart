import '../../../core/geo/geo.dart';
import '../../journey/domain/bus_network.dart';
import '../../journey/domain/direct_bus_planner.dart';

/// What a map marker stands for.
enum MapMarkerKind { origin, boarding, alighting, destination }

/// One point on the journey map. [label] names the place for tooltips and
/// the map's summary.
class MapMarker {
  const MapMarker(this.kind, this.position, this.label);

  final MapMarkerKind kind;
  final LatLng position;
  final String label;

  @override
  bool operator ==(Object other) =>
      other is MapMarker &&
      other.kind == kind &&
      other.position.latitude == position.latitude &&
      other.position.longitude == position.longitude &&
      other.label == label;

  @override
  int get hashCode =>
      Object.hash(kind, position.latitude, position.longitude, label);

  @override
  String toString() => 'MapMarker(${kind.name}, $label)';
}

/// What the journey map draws: markers only, read from the journey that the
/// planner already produced. Pure Dart: no Flutter or map-package import, so
/// it is testable on its own and the map widget stays replaceable (guide
/// §17).
class MapScene {
  const MapScene(this.markers, {this.serviceNumber});

  /// In journey order: origin, boarding stop, alighting stop, destination.
  /// The two stops are present only when a direct bus was suggested.
  final List<MapMarker> markers;

  /// The suggested option's bus, when there is one.
  final String? serviceNumber;

  /// Smallest box holding every marker.
  ({LatLng southWest, LatLng northEast}) get bounds {
    var south = double.infinity, west = double.infinity;
    var north = -double.infinity, east = -double.infinity;
    for (final m in markers) {
      final p = m.position;
      if (p.latitude < south) south = p.latitude;
      if (p.latitude > north) north = p.latitude;
      if (p.longitude < west) west = p.longitude;
      if (p.longitude > east) east = p.longitude;
    }
    return (southWest: LatLng(south, west), northEast: LatLng(north, east));
  }

  /// One sentence for screen readers. The map itself is visual only; the
  /// journey card stays the full, accessible answer.
  String get summary {
    String labelOf(MapMarkerKind kind) =>
        markers.firstWhere((m) => m.kind == kind).label;
    final from = labelOf(MapMarkerKind.origin);
    final to = labelOf(MapMarkerKind.destination);
    final bus = serviceNumber;
    final stops = bus == null
        ? ''
        : ', bus $bus from ${labelOf(MapMarkerKind.boarding)} '
              'to ${labelOf(MapMarkerKind.alighting)}';
    return 'Map of the suggested journey: from $from$stops, to $to. '
        'The journey details are listed above.';
  }

  @override
  bool operator ==(Object other) =>
      other is MapScene &&
      other.serviceNumber == serviceNumber &&
      _listEquals(other.markers, markers);

  @override
  int get hashCode => Object.hash(serviceNumber, Object.hashAll(markers));

  static bool _listEquals(List<MapMarker> a, List<MapMarker> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// The scene for a journey from [origin] to [destination]. [plan] is the
/// planner's current answer (null while it is being found or has failed):
/// only a [DirectBusOptions] adds stops, from its first (suggested) option.
/// Every other answer shows the two ends only. Never plans anything itself.
MapScene buildMapScene({
  required LatLng origin,
  required String originLabel,
  required LatLng destination,
  required String destinationLabel,
  JourneyPlan? plan,
}) {
  final suggested = switch (plan) {
    DirectBusOptions(:final options) when options.isNotEmpty => options.first,
    _ => null,
  };
  String stopLabel(BusStop stop) => '${stop.name} (${stop.code})';
  return MapScene([
    MapMarker(MapMarkerKind.origin, origin, originLabel),
    if (suggested != null) ...[
      MapMarker(
        MapMarkerKind.boarding,
        suggested.board.position,
        stopLabel(suggested.board),
      ),
      MapMarker(
        MapMarkerKind.alighting,
        suggested.alight.position,
        stopLabel(suggested.alight),
      ),
    ],
    MapMarker(MapMarkerKind.destination, destination, destinationLabel),
  ], serviceNumber: suggested?.service.number);
}
