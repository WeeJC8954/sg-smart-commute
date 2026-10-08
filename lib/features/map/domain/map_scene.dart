import '../../../core/config/app_config.dart';
import '../../../core/geo/geo.dart';
import '../../journey/domain/bus_network.dart';
import '../../journey/domain/direct_bus_planner.dart';
import '../../journey/domain/mrt.dart';
import 'ride_geometry.dart';

/// What a map marker stands for. The two MRT kinds (P2-M3) are the journey
/// card's MRT suggestions, informational only.
enum MapMarkerKind {
  origin,
  boarding,
  alighting,
  destination,
  mrtNearOrigin,
  mrtNearDestination,
}

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
      other.position == position &&
      other.label == label;

  @override
  int get hashCode => Object.hash(kind, position, label);

  @override
  String toString() => 'MapMarker(${kind.name}, $label)';
}

/// A straight walking connector between two journey points (P2-M3). An
/// estimate, not a route: the map has no walking geometry (guide §17), and
/// the walking times stay the journey card's.
class MapWalk {
  const MapWalk(this.from, this.to);

  final LatLng from;
  final LatLng to;

  @override
  bool operator ==(Object other) =>
      other is MapWalk && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);

  @override
  String toString() => 'MapWalk($from -> $to)';
}

/// What the journey map draws: markers, and the bus ride when there is one,
/// read from the journey that the planner already produced. Pure Dart: no
/// Flutter or map-package import, so it is testable on its own and the map
/// widget stays replaceable (guide §17).
class MapScene {
  const MapScene(
    this.markers, {
    this.serviceNumber,
    this.ride,
    this.isAlternative = false,
  });

  /// In journey order: origin, boarding stop, alighting stop, destination
  /// (the two stops only when the journey has a direct bus; they are the shown
  /// option's), then the MRT suggestions that are present.
  final List<MapMarker> markers;

  /// The shown option's bus, when there is one.
  final String? serviceNumber;

  /// The shown option's bus ride, whose line is drawn on the road once the
  /// route geometry is known. Null when there is no ride, or when the plan and
  /// the bus network do not agree on it.
  final MapRide? ride;

  /// The shown option is one the user selected instead of the planner's
  /// first (suggested) option (P2-M3).
  final bool isAlternative;

  /// The walking connectors (P2-M3): origin → boarding stop and alighting
  /// stop → destination, straight, when the scene has a bus. Their ends are
  /// the markers themselves. One shorter than
  /// [MapConfig.walkConnectorMinMeters] (the same place) is left out.
  List<MapWalk> get walks {
    LatLng? at(MapMarkerKind kind) {
      for (final m in markers) {
        if (m.kind == kind) return m.position;
      }
      return null;
    }

    final origin = at(MapMarkerKind.origin);
    final boarding = at(MapMarkerKind.boarding);
    final alighting = at(MapMarkerKind.alighting);
    final destination = at(MapMarkerKind.destination);
    if (origin == null ||
        boarding == null ||
        alighting == null ||
        destination == null) {
      return const [];
    }
    return [
      for (final w in [
        MapWalk(origin, boarding),
        MapWalk(alighting, destination),
      ])
        if (haversineMeters(w.from, w.to) >= MapConfig.walkConnectorMinMeters)
          w,
    ];
  }

  /// Smallest box holding every marker and every ride stop.
  ({LatLng southWest, LatLng northEast}) get bounds {
    var south = double.infinity, west = double.infinity;
    var north = -double.infinity, east = -double.infinity;
    for (final p in [...markers.map((m) => m.position), ...?ride?.stops]) {
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
    final journey = isAlternative
        ? 'an alternative journey'
        : 'the suggested journey';
    final walking = walks.isEmpty
        ? ''
        : 'Walks are drawn as straight lines, estimates only. ';
    final mrt = [
      for (final m in markers)
        if (m.kind == MapMarkerKind.mrtNearOrigin ||
            m.kind == MapMarkerKind.mrtNearDestination)
          '${m.label}. ',
    ].join();
    return 'Map of $journey: from $from$stops, to $to. '
        '$walking${mrt}The journey details are listed above.';
  }

  @override
  bool operator ==(Object other) =>
      other is MapScene &&
      other.serviceNumber == serviceNumber &&
      other.ride == ride &&
      other.isAlternative == isAlternative &&
      sameElements(other.markers, markers);

  @override
  int get hashCode =>
      Object.hash(serviceNumber, ride, isAlternative, Object.hashAll(markers));
}

/// The scene for a journey from [origin] to [destination]. [plan] is the
/// planner's current answer (null while it is being found or has failed):
/// only a [DirectBusOptions] adds stops, from the option at [selectedIndex]
/// (the user's selection, P2-M3; 0, the planner's suggestion, by default or
/// when out of range). Every other answer shows the two ends only. [stops] is
/// the bus network's stop table: with it, the shown option also yields the
/// [MapScene.ride]. [mrt] is the journey's settled MRT suggestion (null while
/// it loads or has failed): each side present adds an informational marker at
/// the exit the card's estimate was made to, with the card's wording. Never
/// plans, selects or looks up anything itself.
MapScene buildMapScene({
  required LatLng origin,
  required String originLabel,
  required LatLng destination,
  required String destinationLabel,
  JourneyPlan? plan,
  int selectedIndex = 0,
  ({MrtSuggestion? nearOrigin, MrtSuggestion? nearDestination})? mrt,
  Map<String, BusStop>? stops,
}) {
  final shown = switch (plan) {
    DirectBusOptions(:final options) when options.isNotEmpty =>
      options[selectedIndex >= 0 && selectedIndex < options.length
          ? selectedIndex
          : 0],
    _ => null,
  };
  final ride = shown == null || stops == null ? null : _rideOf(shown, stops);
  String stopLabel(BusStop stop) => '${stop.name} (${stop.code})';
  return MapScene(
    [
      MapMarker(MapMarkerKind.origin, origin, originLabel),
      if (shown != null) ...[
        MapMarker(
          MapMarkerKind.boarding,
          shown.board.position,
          stopLabel(shown.board),
        ),
        MapMarker(
          MapMarkerKind.alighting,
          shown.alight.position,
          stopLabel(shown.alight),
        ),
      ],
      MapMarker(MapMarkerKind.destination, destination, destinationLabel),
      if (mrt?.nearOrigin case final s?)
        MapMarker(
          MapMarkerKind.mrtNearOrigin,
          s.nearestExit.position,
          MrtWording.named(MrtWording.nearOrigin, s.station),
        ),
      if (mrt?.nearDestination case final s?)
        MapMarker(
          MapMarkerKind.mrtNearDestination,
          s.nearestExit.position,
          MrtWording.named(MrtWording.nearDestination, s.station),
        ),
    ],
    serviceNumber: shown?.service.number,
    ride: ride,
    isAlternative:
        plan is DirectBusOptions &&
        shown != null &&
        !identical(shown, plan.options.first),
  );
}

/// [option]'s ride as the stop positions along its direction, boarding to
/// alighting. Null when the network does not hold the option's stops where the
/// plan says (a plan/network mismatch draws no line and changes nothing else).
MapRide? _rideOf(BusOption option, Map<String, BusStop> stops) {
  final codes = option.service.directions[option.direction];
  final from = option.boardIndex, to = from + option.stops;
  if (to >= codes.length ||
      codes[from] != option.board.code ||
      codes[to] != option.alight.code) {
    return null;
  }
  List<LatLng> positions(Iterable<String> run) => [
    for (final c in run) ?stops[c]?.position,
  ];
  final ride = positions(codes.sublist(from, to + 1));
  if (ride.length < 2) return null;
  // The stops just before boarding that make the ride unique on a line that
  // passes the same stops twice (see leadingStopCount).
  final leading = leadingStopCount(codes, from, to);
  return MapRide(
    service: option.service.number,
    sourceDirection: option.service.sourceDirectionOf(option.direction),
    boardIndex: from,
    stops: ride,
    leadingStops: positions(codes.sublist(from - leading, from)),
  );
}
