// E5 Gate 2 prototype of the one-transfer (Bus -> Bus) search, for the
// development-only benchmark in this folder (README.md). Not part of the app
// and not the implementation: Gate 3 writes the real search test-first in
// lib/. It follows docs/e5-gate0-discovery-report.md §6 and the owner's
// rulings in §13 (F1 rules; F2 same stop or a bounded straight-line walk).
import 'package:sg_smart_commute/core/config/app_config.dart';
import 'package:sg_smart_commute/core/geo/geo.dart';
import 'package:sg_smart_commute/features/journey/domain/bus_network.dart';
import 'package:sg_smart_commute/features/journey/domain/direct_bus_planner.dart';
import 'package:sg_smart_commute/features/journey/domain/walking.dart';

/// Built once per network: every (service, direction, position) of each stop,
/// cumulative straight-line metres per direction, and, for a transfer walk,
/// the stops within [transferMeters] of each stop.
class TransferIndex {
  TransferIndex._(
    this.network,
    this.services,
    this.occurrences,
    this.cumulative,
    this.neighbours,
    this.transferMeters,
  );

  factory TransferIndex.build(BusNetwork network, {double transferMeters = 0}) {
    final numbers = network.services.keys.toList()..sort();
    final services = [for (final n in numbers) network.services[n]!];
    final occurrences = <String, List<Occurrence>>{};
    final cumulative = <List<List<double>>>[];
    for (var s = 0; s < services.length; s++) {
      final perDirection = <List<double>>[];
      for (var d = 0; d < services[s].directions.length; d++) {
        final route = services[s].directions[d];
        final cum = List<double>.filled(route.length, 0);
        for (var p = 0; p < route.length; p++) {
          (occurrences[route[p]] ??= []).add((service: s, direction: d, at: p));
          if (p > 0) {
            cum[p] =
                cum[p - 1] +
                haversineMeters(
                  network.stops[route[p - 1]]!.position,
                  network.stops[route[p]]!.position,
                );
          }
        }
        perDirection.add(cum);
      }
      cumulative.add(perDirection);
    }
    final neighbours = <String, List<String>>{};
    if (transferMeters > 0) {
      // ~250 m cells; a neighbour within transferMeters is in the 3 x 3 block.
      const cell = 0.00225;
      final grid = <(int, int), List<BusStop>>{};
      (int, int) key(LatLng p) =>
          ((p.latitude / cell).floor(), (p.longitude / cell).floor());
      for (final stop in network.stops.values) {
        (grid[key(stop.position)] ??= []).add(stop);
      }
      for (final stop in network.stops.values) {
        final (r, c) = key(stop.position);
        final near = <String>[];
        for (var dr = -1; dr <= 1; dr++) {
          for (var dc = -1; dc <= 1; dc++) {
            for (final other in grid[(r + dr, c + dc)] ?? const <BusStop>[]) {
              if (other.code != stop.code &&
                  haversineMeters(stop.position, other.position) <=
                      transferMeters) {
                near.add(other.code);
              }
            }
          }
        }
        near.sort();
        neighbours[stop.code] = near;
      }
    }
    return TransferIndex._(
      network,
      services,
      occurrences,
      cumulative,
      neighbours,
      transferMeters,
    );
  }

  final BusNetwork network;
  final List<BusService> services;
  final Map<String, List<Occurrence>> occurrences;
  final List<List<List<double>>> cumulative;
  final Map<String, List<String>> neighbours;
  final double transferMeters;

  int get occurrenceCount =>
      occurrences.values.fold(0, (sum, list) => sum + list.length);
}

typedef Occurrence = ({int service, int direction, int at});

/// One ride: [service] in [direction] from position [from] to [to].
typedef Ride = ({int service, int direction, int from, int to});

class TransferJourney {
  TransferJourney({
    required this.first,
    required this.second,
    required this.walkToStop,
    required this.transferWalk,
    required this.walkFromStop,
    required this.score,
    required this.detourRatio,
  });

  final Ride first;
  final Ride second;
  final WalkEstimate walkToStop;
  final WalkEstimate transferWalk;
  final WalkEstimate walkFromStop;

  /// walk + 1.5 x stops + transfer walk + 1.5 x stops + walk (no penalty:
  /// under F3 option 1 transfers are only ranked against each other).
  final double score;

  /// Straight-line metres between consecutive stops of both rides, over the
  /// straight line from origin to destination.
  final double detourRatio;

  int get stops => (first.to - first.from) + (second.to - second.from);
}

typedef _Label = ({int service, int direction, int from, int to, double score});

class TransferSearchResult {
  TransferSearchResult(this.journeys, this.radiusMeters, this.work);
  final List<TransferJourney> journeys;
  final double radiusMeters;

  /// Labels plus join pairs examined, a machine-independent cost measure.
  final int work;
}

/// One-transfer search for a pair the direct planner answered with
/// [NoDirectBus]. Candidate stops at 400 m, then once at 800 m, as the direct
/// planner. Rules: forward order on both rides (first occurrence after the
/// boarding position, as `planDirectBus`), different services, the second
/// ride never returns to a stop of the first (other than the transfer stop),
/// the detour limit, and the best journey per (service A, service B) pair.
/// Labels keep the best ride per (stop, service, direction) only.
TransferSearchResult searchOneTransfer(
  TransferIndex index,
  LatLng origin,
  LatLng destination, {
  double? detourLimit,
  int maxResults = 3,
}) {
  var work = 0;
  for (final radius in const [
    JourneyConfig.stopRadiusMeters,
    JourneyConfig.widenedStopRadiusMeters,
  ]) {
    final result = _attempt(index, origin, destination, radius, detourLimit);
    work += result.work;
    if (result.journeys.isNotEmpty ||
        radius == JourneyConfig.widenedStopRadiusMeters) {
      result.journeys.sort(_compare(index));
      return TransferSearchResult(
        result.journeys.take(maxResults).toList(),
        radius,
        work,
      );
    }
  }
  throw StateError('unreachable');
}

({List<TransferJourney> journeys, int work}) _attempt(
  TransferIndex index,
  LatLng origin,
  LatLng destination,
  double radius,
  double? detourLimit,
) {
  final network = index.network;
  const stopWeight = JourneyConfig.stopWeight;
  final near = <String, WalkEstimate>{};
  final far = <String, WalkEstimate>{};
  for (final stop in network.stops.values) {
    if (haversineMeters(origin, stop.position) <= radius) {
      near[stop.code] = WalkEstimate.between(origin, stop.position);
    }
    if (haversineMeters(destination, stop.position) <= radius) {
      far[stop.code] = WalkEstimate.between(stop.position, destination);
    }
  }
  if (near.isEmpty || far.isEmpty) return (journeys: [], work: 0);

  var work = 0;
  final legA = <String, Map<int, _Label>>{};
  for (final MapEntry(key: code, value: walk) in near.entries) {
    for (final o in index.occurrences[code] ?? const <Occurrence>[]) {
      final route = index.services[o.service].directions[o.direction];
      final seen = <String>{};
      for (var k = o.at + 1; k < route.length; k++) {
        final x = route[k];
        if (x == route[o.at] || !seen.add(x)) continue;
        work++;
        final score = walk.minutes + stopWeight * (k - o.at);
        final labels = legA[x] ??= {};
        final key = o.service * 2 + o.direction;
        final old = labels[key];
        if (old == null || score < old.score) {
          labels[key] = (
            service: o.service,
            direction: o.direction,
            from: o.at,
            to: k,
            score: score,
          );
        }
      }
    }
  }
  final legB = <String, Map<int, _Label>>{};
  for (final MapEntry(key: code, value: walk) in far.entries) {
    for (final o in index.occurrences[code] ?? const <Occurrence>[]) {
      final route = index.services[o.service].directions[o.direction];
      for (var m = o.at - 1; m >= 0; m--) {
        if (route[m] == route[o.at]) break; // o.at is no longer the first
        work++;
        final score = walk.minutes + stopWeight * (o.at - m);
        final labels = legB[route[m]] ??= {};
        final key = o.service * 2 + o.direction;
        final old = labels[key];
        if (old == null || score < old.score) {
          labels[key] = (
            service: o.service,
            direction: o.direction,
            from: m,
            to: o.at,
            score: score,
          );
        }
      }
    }
  }

  final straight = haversineMeters(origin, destination);
  final best = <int, TransferJourney>{};
  final compare = _compare(index);
  for (final MapEntry(key: x, value: atX) in legA.entries) {
    final ys = [x, ...?index.neighbours[x]];
    for (final y in ys) {
      final atY = legB[y];
      if (atY == null) continue;
      final transfer = WalkEstimate.between(
        network.stops[x]!.position,
        network.stops[y]!.position,
      );
      for (final a in atX.values) {
        for (final b in atY.values) {
          work++;
          if (a.service == b.service) continue;
          final routeA = index.services[a.service].directions[a.direction];
          final routeB = index.services[b.service].directions[b.direction];
          final walkTo = near[routeA[a.from]]!;
          final walkFrom = far[routeB[b.to]]!;
          final rideMeters =
              index.cumulative[a.service][a.direction][a.to] -
              index.cumulative[a.service][a.direction][a.from] +
              index.cumulative[b.service][b.direction][b.to] -
              index.cumulative[b.service][b.direction][b.from];
          final detour = rideMeters / straight;
          if (detourLimit != null && detour > detourLimit) continue;
          final journey = TransferJourney(
            first: (
              service: a.service,
              direction: a.direction,
              from: a.from,
              to: a.to,
            ),
            second: (
              service: b.service,
              direction: b.direction,
              from: b.from,
              to: b.to,
            ),
            walkToStop: walkTo,
            transferWalk: transfer,
            walkFromStop: walkFrom,
            score: a.score + b.score + transfer.minutes,
            detourRatio: detour,
          );
          final pair = a.service * 100000 + b.service;
          final old = best[pair];
          if (old != null && compare(journey, old) >= 0) continue;
          if (_returnsToFirstRide(routeA, a, routeB, b)) continue;
          best[pair] = journey;
        }
      }
    }
  }
  return (journeys: best.values.toList(), work: work);
}

/// The second ride boards or stops at a stop the first ride already used
/// (its board stop up to, but not including, the transfer stop).
bool _returnsToFirstRide(
  List<String> routeA,
  _Label a,
  List<String> routeB,
  _Label b,
) {
  final used = {for (var p = a.from; p < a.to; p++) routeA[p]};
  for (var p = b.from; p <= b.to; p++) {
    if (used.contains(routeB[p])) return true;
  }
  return false;
}

/// Score, total stops, service A then B in natural order, then the board,
/// transfer and alight stop codes.
int Function(TransferJourney, TransferJourney) _compare(TransferIndex index) =>
    (a, b) {
      String code(Ride r, int at) =>
          index.services[r.service].directions[r.direction][at];
      for (final c in [
        a.score.compareTo(b.score),
        a.stops.compareTo(b.stops),
        compareServiceNumbers(
          index.services[a.first.service].number,
          index.services[b.first.service].number,
        ),
        compareServiceNumbers(
          index.services[a.second.service].number,
          index.services[b.second.service].number,
        ),
        code(a.first, a.first.from).compareTo(code(b.first, b.first.from)),
        code(a.first, a.first.to).compareTo(code(b.first, b.first.to)),
        code(a.second, a.second.from).compareTo(code(b.second, b.second.from)),
        code(a.second, a.second.to).compareTo(code(b.second, b.second.to)),
      ]) {
        if (c != 0) return c;
      }
      return 0;
    };
