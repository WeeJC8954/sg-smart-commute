import '../../../core/geo/geo.dart';

/// A bus stop from busrouter `stops.min.json` (guide v2.1 §9.1). The source
/// stores `[longitude, latitude, name, road]`; [position] is latitude-first.
class BusStop {
  const BusStop({
    required this.code,
    required this.position,
    required this.name,
    required this.road,
  });

  /// Five-digit LTA stop code, kept as a string (`01012`).
  final String code;
  final LatLng position;
  final String name;
  final String road;

  @override
  String toString() => 'BusStop($code $name)';
}

/// A bus service from busrouter `services.min.json`: one or two ordered stop
/// lists, one per direction. Direction is never inferred from geography.
class BusService {
  const BusService({
    required this.number,
    required this.name,
    required this.directions,
    this.sourceDirections,
  });

  /// Service number as published, e.g. `65`, `100A`, `CT18`.
  final String number;

  /// busrouter's label, e.g. `Tampines Int ⇄ HarbourFront Int`.
  final String name;

  /// Ordered stop codes per direction (1 or 2 lists).
  final List<List<String>> directions;

  /// busrouter's direction index for each kept direction; null when none was
  /// dropped (then the index is the same).
  final List<int>? sourceDirections;

  /// busrouter's direction index for [direction] (an index into [directions]).
  int sourceDirectionOf(int direction) =>
      sourceDirections?[direction] ?? direction;
}

class BusNetwork {
  const BusNetwork({required this.stops, required this.services});

  final Map<String, BusStop> stops;
  final Map<String, BusService> services;
}
