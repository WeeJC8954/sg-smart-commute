import 'bus_arrival.dart';

/// Live arrivals for one bus stop (guide v2.1 §10). Implementations throw a
/// typed AppFailure. Overridden with a fake in tests.
abstract interface class BusArrivalRepository {
  Future<StopArrivals> arrivalsAt(String busStopCode);
}
