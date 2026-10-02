import '../../../core/config/app_config.dart';

/// Crowding of an arriving bus (LTA codes SEA / SDA / LSD).
enum BusLoad {
  seatsAvailable('Seats available'),
  standingAvailable('Standing available'),
  limitedStanding('Limited standing');

  const BusLoad(this.label);

  /// Shown as text, never as colour alone (§17 accessibility).
  final String label;
}

/// Vehicle type (LTA codes SD / DD / BD).
enum BusType {
  singleDeck('Single deck'),
  doubleDeck('Double deck'),
  bendy('Bendy bus');

  const BusType(this.label);
  final String label;
}

/// One estimated arrival of [serviceNo] at [busStopCode] (guide v2.1 §10).
/// Everything except the service and stop is optional: a field the provider
/// leaves out or sends in an unknown form is null, never guessed.
class BusArrival {
  const BusArrival({
    required this.serviceNo,
    required this.busStopCode,
    required this.estimatedArrival,
    this.load,
    this.wheelchairAccessible,
    this.type,
    this.monitored,
    this.visitNumber,
    required this.source,
  });

  final String serviceNo;
  final String busStopCode;

  /// UTC. Null when the provider gave no (valid) time for this slot.
  final DateTime? estimatedArrival;
  final BusLoad? load;
  final bool? wheelchairAccessible;
  final BusType? type;

  /// True when the estimate comes from the bus's live position, false when it
  /// is based on the schedule (LTA `Monitored` 1 / 0).
  final bool? monitored;

  /// LTA `VisitNumber`: 2 when a loop bus is on its second visit to the stop.
  final int? visitNumber;

  /// e.g. "ArriveLah".
  final String source;
}

/// The arrivals a provider listed for one service at one stop, in its order
/// (next, then the following two).
class ServiceArrivals {
  const ServiceArrivals({required this.serviceNo, required this.arrivals});
  final String serviceNo;
  final List<BusArrival> arrivals;
}

/// Every service listed at one stop in one provider response.
class StopArrivals {
  const StopArrivals({required this.busStopCode, required this.services});
  final String busStopCode;
  final List<ServiceArrivals> services;
}

/// The next arrivals of [serviceNo] at [stop], soonest first, at most
/// [BusArrivalConfig.maxShown]. Only arrivals with a time are returned, so an
/// empty list means "no live arrival available": the service is not listed
/// (which says nothing about whether the route is valid), or none of its slots
/// has a time.
///
/// [boardsAtLoopTerminal]: the rider boards a loop service at the stop where
/// the loop starts and ends. There, LTA's visit 2 is a bus finishing the loop
/// (it terminates), so only visit-1 departures are kept.
List<BusArrival> nextArrivals(
  StopArrivals stop,
  String serviceNo, {
  bool boardsAtLoopTerminal = false,
}) {
  final wanted = _normalise(serviceNo);
  final arrivals = [
    for (final s in stop.services)
      if (_normalise(s.serviceNo) == wanted)
        for (final a in s.arrivals)
          if (a.estimatedArrival != null &&
              !(boardsAtLoopTerminal && a.visitNumber == 2))
            a,
  ]..sort((a, b) => a.estimatedArrival!.compareTo(b.estimatedArrival!));
  return arrivals.take(BusArrivalConfig.maxShown).toList();
}

String _normalise(String serviceNo) => serviceNo.trim().toUpperCase();

/// "Arr" when [eta] is at most [BusArrivalConfig.arrivingWithin] after [now]
/// (or already past); otherwise whole minutes, rounded down ("7 min"). Both
/// are UTC instants.
String etaLabel(DateTime eta, DateTime now) {
  final until = eta.difference(now);
  if (until <= BusArrivalConfig.arrivingWithin) return 'Arr';
  return '${until.inMinutes} min';
}
