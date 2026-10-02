import 'dart:async';

import 'package:sg_smart_commute/core/errors/app_failure.dart';
import 'package:sg_smart_commute/features/bus_arrival/domain/bus_arrival.dart';
import 'package:sg_smart_commute/features/bus_arrival/domain/bus_arrival_repository.dart';

import 'fake_environment_repository.dart';

/// A fake arrival at [stop] for [service], [after] from [fakeNow].
BusArrival fakeArrival(
  String stop,
  String service,
  Duration after, {
  BusLoad? load = BusLoad.seatsAvailable,
  bool? wheelchairAccessible = true,
  BusType? type = BusType.doubleDeck,
  bool? monitored = true,
  int? visitNumber = 1,
  DateTime? from,
}) => BusArrival(
  serviceNo: service,
  busStopCode: stop,
  estimatedArrival: (from ?? fakeNow).add(after),
  load: load,
  wheelchairAccessible: wheelchairAccessible,
  type: type,
  monitored: monitored,
  visitNumber: visitNumber,
  source: 'ArriveLah (fake)',
);

/// Default fake arrivals for the fake network's Bishan → VivoCity options
/// (test/fakes/fake_bus_network.dart), counted from [from] (default
/// [fakeNow]):
///
///   BSH2: F20 at +30 s ("Arr"), +7 min, +19 min
///   BSH1: F10 at +4 min, +12 min (scheduled); F30 at +2 min only
///         (F10 and F30 board at the same stop: one request serves both)
Map<String, StopArrivals> fakeStopArrivals({DateTime? from}) => {
  'BSH2': StopArrivals(
    busStopCode: 'BSH2',
    services: [
      ServiceArrivals(
        serviceNo: 'F20',
        arrivals: [
          fakeArrival('BSH2', 'F20', const Duration(seconds: 30), from: from),
          fakeArrival(
            'BSH2',
            'F20',
            const Duration(minutes: 7),
            load: BusLoad.standingAvailable,
            from: from,
          ),
          fakeArrival('BSH2', 'F20', const Duration(minutes: 19), from: from),
        ],
      ),
    ],
  ),
  'BSH1': StopArrivals(
    busStopCode: 'BSH1',
    services: [
      ServiceArrivals(
        serviceNo: 'F10',
        arrivals: [
          fakeArrival('BSH1', 'F10', const Duration(minutes: 4), from: from),
          fakeArrival(
            'BSH1',
            'F10',
            const Duration(minutes: 12),
            monitored: false,
            from: from,
          ),
        ],
      ),
      ServiceArrivals(
        serviceNo: 'F30',
        arrivals: [
          fakeArrival(
            'BSH1',
            'F30',
            const Duration(minutes: 2),
            load: BusLoad.limitedStanding,
            wheelchairAccessible: false,
            type: BusType.singleDeck,
            from: from,
          ),
        ],
      ),
    ],
  ),
};

/// Controllable [BusArrivalRepository]. Answers from [stops] (an unknown stop
/// lists no services), or throws [failure] (every stop) / [failures] (per
/// stop). [hold] keeps a stop's request pending until [release]. [calls]
/// counts requests per stop.
class FakeBusArrivalRepository implements BusArrivalRepository {
  FakeBusArrivalRepository({Map<String, StopArrivals>? stops, this.failure})
    : stops = stops ?? fakeStopArrivals();

  Map<String, StopArrivals> stops;
  AppFailure? failure;
  final Map<String, AppFailure> failures = {};
  final Map<String, int> calls = {};
  final Map<String, Completer<void>> _gates = {};

  int get totalCalls => calls.values.fold(0, (a, b) => a + b);

  void hold(String stop) => _gates[stop] = Completer<void>();
  void release(String stop) => _gates.remove(stop)?.complete();

  @override
  Future<StopArrivals> arrivalsAt(String busStopCode) async {
    calls[busStopCode] = (calls[busStopCode] ?? 0) + 1;
    final gate = _gates[busStopCode];
    if (gate != null) await gate.future;
    final f = failures[busStopCode] ?? failure;
    if (f != null) throw f;
    return stops[busStopCode] ??
        StopArrivals(busStopCode: busStopCode, services: const []);
  }
}
