import '../../../core/errors/app_failure.dart';
import '../../../core/errors/failure_guard.dart';
import '../../../core/time/clock.dart';
import 'bus_arrival.dart';
import 'bus_arrival_repository.dart';

/// The one place live-arrival requests are made from (guide v2.1 §15):
/// - a stop's arrivals are reused for [ttl] after they arrive, so repeated
///   Refresh taps and several displayed services boarding at the same stop
///   share one request;
/// - concurrent requests for the same stop share one in-flight future;
/// - failures are not cached, so the next request (Retry) tries again.
///
/// Session-only and in memory. Every error leaves as a typed [AppFailure].
class BusArrivalCache {
  BusArrivalCache(this._repository, this._clock, {required this.ttl});

  final BusArrivalRepository _repository;
  final Clock _clock;
  final Duration ttl;

  final Map<String, ({StopArrivals arrivals, DateTime at})> _fresh = {};
  final Map<String, Future<StopArrivals>> _inFlight = {};

  Future<StopArrivals> arrivalsAt(String busStopCode) {
    final cached = _fresh[busStopCode];
    if (cached != null && _clock().difference(cached.at) < ttl) {
      return Future.value(cached.arrivals);
    }
    final pending = _inFlight[busStopCode];
    if (pending != null) return pending;
    // Block body on purpose: `remove` returns this very future, and
    // whenComplete would wait on a returned future (a self-deadlock).
    final future = _load(busStopCode).whenComplete(() {
      _inFlight.remove(busStopCode);
    });
    _inFlight[busStopCode] = future;
    return future;
  }

  Future<StopArrivals> _load(String busStopCode) async {
    final arrivals = await guardAppFailure(
      () => _repository.arrivalsAt(busStopCode),
      context: 'bus arrivals',
    );
    _fresh[busStopCode] = (arrivals: arrivals, at: _clock());
    return arrivals;
  }
}
