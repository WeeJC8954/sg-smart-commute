import '../../../core/config/app_config.dart';

/// Crowding of an arriving bus (LTA codes SEA / SDA / LSD).
enum BusLoad {
  seatsAvailable('Seats available'),
  standingAvailable('Standing available'),
  limitedStanding('Limited standing');

  const BusLoad(this.label);

  /// Shown as text, never as colour alone (§16 accessibility).
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
/// leaves out or sends in an unknown form is null, never guessed. The fields
/// follow the guide's model, including [busStopCode] and [source], which the
/// UI does not read yet.
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

/// Every service listed at one stop in one provider response (the stop is
/// the key it is looked up by, and each [BusArrival.busStopCode]).
class StopArrivals {
  const StopArrivals({required this.services});
  final List<ServiceArrivals> services;
}

/// The next arrivals of [serviceNo] at [stop] as of [now], soonest first, at
/// most [BusArrivalConfig.maxShown]. Only arrivals with a plausible time
/// ([isPlausibleEta]) are returned, so an empty list means "no live arrival
/// available" (shown as such): the service is not listed (which says nothing
/// about whether the route is valid), none of its slots has a usable time, or
/// the loop-terminal rule below removed every timed arrival.
///
/// [boardsAtLoopTerminal]: the rider boards a loop service at the stop where
/// the loop starts and ends. There, an arrival with LTA visit number 2 is a
/// bus finishing the loop (it terminates), so it is excluded. Visit-1 arrivals
/// are kept, and so are arrivals whose visit number is missing or unknown:
/// they are not discarded on missing metadata.
List<BusArrival> nextArrivals(
  StopArrivals stop,
  String serviceNo, {
  required DateTime now,
  bool boardsAtLoopTerminal = false,
}) {
  final wanted = _normalise(serviceNo);
  final arrivals = [
    for (final s in stop.services)
      if (_normalise(s.serviceNo) == wanted)
        for (final a in s.arrivals)
          if (a.estimatedArrival case final eta?
              when isPlausibleEta(eta, now) &&
                  !(boardsAtLoopTerminal && a.visitNumber == 2))
            a,
  ]..sort((a, b) => a.estimatedArrival!.compareTo(b.estimatedArrival!));
  return arrivals.take(BusArrivalConfig.maxShown).toList();
}

/// Whether [eta] is a believable estimate at [now]: at most
/// [BusArrivalConfig.maxPastEta] ago and at most
/// [BusArrivalConfig.maxFutureEta] ahead. ArriveLah is an unofficial proxy,
/// so a replayed old response or a bogus far-future time is treated as no
/// time, never shown as "Arr" or as thousands of minutes.
bool isPlausibleEta(DateTime eta, DateTime now) {
  final until = eta.difference(now);
  return until >= -BusArrivalConfig.maxPastEta &&
      until <= BusArrivalConfig.maxFutureEta;
}

String _normalise(String serviceNo) => serviceNo.trim().toUpperCase();

/// Whole minutes until [eta], rounded down, or null when the bus is arriving:
/// at most [BusArrivalConfig.arrivingWithin] after [now], or already past.
/// Both are UTC instants.
int? minutesUntil(DateTime eta, DateTime now) {
  final until = eta.difference(now);
  return until <= BusArrivalConfig.arrivingWithin ? null : until.inMinutes;
}

/// "Arr", or whole minutes rounded down ("7 min"); see [minutesUntil].
String etaLabel(DateTime eta, DateTime now) => switch (minutesUntil(eta, now)) {
  null => 'Arr',
  final minutes => '$minutes min',
};

/// What a screen reader says for [etaLabel]: "arriving now", "1 minute" or
/// "N minutes". Derived from the same duration, never from the label text.
String etaSpoken(DateTime eta, DateTime now) =>
    switch (minutesUntil(eta, now)) {
      null => 'arriving now',
      1 => '1 minute',
      final minutes => '$minutes minutes',
    };
