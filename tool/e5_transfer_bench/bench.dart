// E5 Gate 2 development-only benchmark (README.md in this folder). Runs the
// same fixed inputs on the Dart VM (vm_main.dart) and in Chrome through
// dart2js (web_main.dart). Everything above the "timings" line is
// deterministic and must be identical on both platforms.
import 'dart:convert';
import 'dart:math' as math;

import 'package:sg_smart_commute/core/geo/geo.dart';
import 'package:sg_smart_commute/features/journey/data/busrouter_parser.dart';
import 'package:sg_smart_commute/features/journey/domain/bus_network.dart';
import 'package:sg_smart_commute/features/journey/domain/direct_bus_planner.dart';
import 'package:sg_smart_commute/features/journey/domain/journey_estimate.dart';
import 'package:sg_smart_commute/features/journey/domain/walking.dart';

import 'transfer_search.dart';

const int seed = 20261106;
const int samplePairs = 500;
const double minPairMeters = 1500;

/// Each end stands this far (degrees, ~44 m each way) from its stop.
const double offsetDegrees = 0.0004;

const List<double?> detourLimits = [2.0, 2.5, 3.0, null];
const List<double> transferWalks = [0, 150];

/// Named fixtures: stop pairs with no direct bus (checked by the run), from
/// short cross-town to cross-island trips.
const List<(String, String, String)> namedFixtures = [
  ('Toa Payoh Int -> Yishun Int', '52009', '59009'),
  ('Bedok Int -> Punggol Int', '84009', '65009'),
  ('Yishun Int -> Changi Village Ter', '59009', '99009'),
  ('Sengkang Int -> Jurong East Int', '67009', '28009'),
  ('Clementi Int -> Yishun Int', '17009', '59009'),
  ('Bt Batok Int -> Bedok Int', '43009', '84009'),
  ('Toa Payoh Int -> Changi Airport T2', '52009', '95019'),
  ('Woodlands Int -> Pasir Ris Int', '46008', '77009'),
  ('Punggol Int -> Kent Ridge Ter', '65009', '16009'),
  ('Changi Airport T2 -> Jurong East Int', '95019', '28009'),
  ('Changi Village Ter -> Boon Lay Int', '99009', '22009'),
  ('Pasir Ris Int -> Clementi Int', '77009', '17009'),
];

typedef Pair = ({String label, LatLng origin, LatLng destination});

String runBenchmark(
  String stopsJson,
  String servicesJson, {
  required String platform,
}) {
  final timings = StringBuffer();
  final watch = Stopwatch()..start();
  final stops = parseBusrouterStops(jsonDecode(stopsJson));
  final services = parseBusrouterServices(jsonDecode(servicesJson), stops);
  final network = BusNetwork(stops: stops, services: services);
  final parseMs = _ms(watch);

  final indexes = <double, TransferIndex>{};
  final buildMs = <double, double>{};
  for (final walk in transferWalks) {
    watch.reset();
    indexes[walk] = TransferIndex.build(network, transferMeters: walk);
    buildMs[walk] = _ms(watch);
  }

  final sample = _sample(network);
  final named = [
    for (final (label, from, to) in namedFixtures)
      (
        label: label,
        origin: _offset(stops[from]!.position),
        destination: _offset(stops[to]!.position),
      ),
  ];

  // Cold: the first direct plan and the first search of the session.
  final firstNoDirect = named.first;
  watch.reset();
  planDirectBus(network, firstNoDirect.origin, firstNoDirect.destination);
  final coldPlanMs = _ms(watch);
  watch.reset();
  searchOneTransfer(
    indexes[0]!,
    firstNoDirect.origin,
    firstNoDirect.destination,
    detourLimit: 2.5,
  );
  final coldSearchMs = _ms(watch);

  final plans = [
    for (final p in sample) planDirectBus(network, p.origin, p.destination),
  ];
  final noDirect = [
    for (var i = 0; i < sample.length; i++)
      if (plans[i] is NoDirectBus) sample[i],
  ];

  // Warm timings: one untimed pass, then three timed passes.
  final planTimes = <double>[];
  for (var pass = 0; pass < 4; pass++) {
    for (final p in sample) {
      watch.reset();
      planDirectBus(network, p.origin, p.destination);
      if (pass > 0) planTimes.add(_ms(watch));
    }
  }
  final searchTimes = <double, List<double>>{};
  final work = <double, int>{};
  for (final walk in transferWalks) {
    final times = searchTimes[walk] = [];
    for (var pass = 0; pass < 4; pass++) {
      for (final p in noDirect) {
        watch.reset();
        final r = searchOneTransfer(
          indexes[walk]!,
          p.origin,
          p.destination,
          detourLimit: 2.5,
        );
        if (pass > 0) times.add(_ms(watch));
        work[walk] = math.max(work[walk] ?? 0, r.work);
      }
    }
  }

  timings
    ..writeln('== timings ($platform) ==')
    ..writeln('parse (jsonDecode + app parser), cold: ${_f(parseMs)} ms')
    ..writeln(
      'index build, cold: same stop ${_f(buildMs[0]!)} ms; '
      '150 m ${_f(buildMs[150]!)} ms',
    )
    ..writeln(
      'first planDirectBus ${_f(coldPlanMs)} ms; first search '
      '(same stop, 2.5) ${_f(coldSearchMs)} ms',
    )
    ..writeln(
      'planDirectBus, warm, ${planTimes.length} runs: ${_dist(planTimes)}',
    );
  for (final walk in transferWalks) {
    timings.writeln(
      'search ${_walkName(walk)}, limit 2.5, warm, '
      '${searchTimes[walk]!.length} runs: ${_dist(searchTimes[walk]!)}; '
      'max work ${work[walk]}',
    );
  }

  final out = StringBuffer()
    ..writeln('E5 one-transfer benchmark')
    ..writeln(
      'input: ${stops.length} stops, ${services.length} services, '
      '${services.values.fold(0, (s, v) => s + v.directions.length)} '
      'directions, ${indexes[0]!.occurrenceCount} occurrences',
    )
    ..writeln(
      'sample: seed $seed, $samplePairs stop pairs >= ${minPairMeters.round()} '
      'm apart, each end offset $offsetDegrees deg lat and lng',
    )
    ..writeln('== results ==');
  _sampleSection(out, network, indexes, sample, plans, noDirect);
  _namedSection(out, network, indexes, named);
  return '$out$timings';
}

void _sampleSection(
  StringBuffer out,
  BusNetwork network,
  Map<double, TransferIndex> indexes,
  List<Pair> sample,
  List<JourneyPlan> plans,
  List<Pair> noDirect,
) {
  final direct = plans.whereType<DirectBusOptions>().length;
  final walkOnly = plans.whereType<WalkOnly>().length;
  final noStops = plans.whereType<NoNearbyStops>().length;
  out
    ..writeln(
      'direct bus ${_pc(direct, sample.length)}; no direct bus '
      '${_pc(noDirect.length, sample.length)}; no nearby stops $noStops; '
      'walk only $walkOnly',
    )
    ..writeln()
    ..writeln(
      'Coverage of the ${noDirect.length} no-direct pairs, and plausibility '
      'of the best journey (minutes exclude any wait):',
    )
    ..writeln(
      'walk | limit | found | 1.5-5 km | 5-10 km | 10-15 km | >15 km | '
      'detour p50/p95/max | est. min p50/p95 | km/h p5/p50 | '
      'slower than walking',
    );

  final best = <(double, double?), List<TransferJourney?>>{};
  for (final walk in transferWalks) {
    for (final limit in detourLimits) {
      final rows = best[(walk, limit)] = [
        for (final p in noDirect)
          searchOneTransfer(
            indexes[walk]!,
            p.origin,
            p.destination,
            detourLimit: limit,
          ).journeys.firstOrNull,
      ];
      final bands = List.filled(4, 0);
      final bandTotals = List.filled(4, 0);
      final detours = <double>[];
      final minutes = <double>[];
      final speeds = <double>[];
      var slower = 0;
      for (var i = 0; i < noDirect.length; i++) {
        final band = _band(noDirect[i]);
        bandTotals[band]++;
        final j = rows[i];
        if (j == null) continue;
        bands[band]++;
        detours.add(j.detourRatio);
        final est = _estimate(network, indexes[walk]!, j);
        if (est != null) {
          minutes.add(est.toDouble());
          speeds.add(double.parse(_speed(noDirect[i], est)));
          if (est > _walkAll(noDirect[i])) slower++;
        }
      }
      final found = rows.whereType<TransferJourney>().length;
      out.writeln(
        '${_walkName(walk)} | ${_limit(limit)} | '
        '${_pc(found, noDirect.length)} | '
        '${[for (var b = 0; b < 4; b++) '${bands[b]}/${bandTotals[b]}'].join(' | ')} | '
        '${_p(detours, 50)}/${_p(detours, 95)}/${_p(detours, 100)} | '
        '${_p(minutes, 50, 0)}/${_p(minutes, 95, 0)} | '
        '${_p(speeds, 5, 1)}/${_p(speeds, 50, 1)} | $slower',
      );
    }
  }

  out
    ..writeln()
    ..writeln(
      'Ranking by score against E2 minutes (limit 2.5, the 3 journeys '
      'shown): pairs where a lower-ranked journey has a shorter estimate',
    );
  for (final walk in transferWalks) {
    final gaps = <double>[];
    var shown = 0;
    for (final p in noDirect) {
      final journeys = searchOneTransfer(
        indexes[walk]!,
        p.origin,
        p.destination,
        detourLimit: 2.5,
      ).journeys;
      if (journeys.length < 2) continue;
      shown++;
      final first = _estimate(network, indexes[walk]!, journeys.first);
      final fastest = journeys
          .map((j) => _estimate(network, indexes[walk]!, j))
          .whereType<int>()
          .fold<int?>(null, (m, e) => m == null || e < m ? e : m);
      if (first != null && fastest != null && fastest < first) {
        gaps.add((first - fastest).toDouble());
      }
    }
    out.writeln(
      '${_walkName(walk)}: ${gaps.length} of $shown pairs with 2+ journeys; '
      'minutes saved p50/max ${_p(gaps, 50, 0)}/${_p(gaps, 100, 0)}',
    );
  }

  out
    ..writeln()
    ..writeln(
      'Journeys gained by each step of the limit (same stop; best journey, '
      'first 6 by sample order):',
    );
  for (final (lower, upper) in const [(2.0, 2.5), (2.5, 3.0), (3.0, null)]) {
    final low = best[(0.0, lower)]!;
    final high = best[(0.0, upper)]!;
    final gained = [
      for (var i = 0; i < noDirect.length; i++)
        if (low[i] == null && high[i] != null) i,
    ];
    final slower = gained
        .where(
          (i) =>
              (_estimate(network, indexes[0]!, high[i]!) ?? 0) >
              _walkAll(noDirect[i]),
        )
        .length;
    out.writeln(
      '${_limit(lower)} -> ${_limit(upper)}: ${gained.length} pairs gained, '
      '$slower of them slower than walking the whole way',
    );
    for (final i in gained.take(6)) {
      out.writeln(
        '  ${_describe(network, indexes[0]!, noDirect[i], high[i]!)}',
      );
    }
  }

  out
    ..writeln()
    ..writeln(
      'Pairs found only with a 150 m transfer walk (limit 2.5), with the '
      'two stops of the walk:',
    );
  final same = best[(0.0, 2.5)]!;
  final walk150 = best[(150.0, 2.5)]!;
  var onlyWalk = 0;
  var sameRoad = 0;
  final examples = <String>[];
  for (var i = 0; i < noDirect.length; i++) {
    if (same[i] != null || walk150[i] == null) continue;
    onlyWalk++;
    final j = walk150[i]!;
    final x = _code(indexes[150]!, j.first, j.first.to);
    final y = _code(indexes[150]!, j.second, j.second.from);
    final sx = network.stops[x]!;
    final sy = network.stops[y]!;
    if (sx.road == sy.road) sameRoad++;
    if (examples.length < 8) {
      examples.add(
        '  ${sx.code} ${sx.name} (${sx.road}) -> ${sy.code} ${sy.name} '
        '(${sy.road}), ${j.transferWalk.straightLineMeters.round()} m',
      );
    }
  }
  var walkBest = 0;
  for (var i = 0; i < noDirect.length; i++) {
    final a = same[i];
    final b = walk150[i];
    if (a != null && b != null && b.transferWalk.straightLineMeters > 0) {
      walkBest++;
    }
  }
  out
    ..writeln(
      '$onlyWalk pairs ($sameRoad with both stops on the same road name); '
      'in $walkBest more pairs a walking transfer is the best journey',
    )
    ..writeAll(examples, '\n')
    ..writeln();
  final walking = [
    for (final j in walk150)
      if (j != null && j.transferWalk.straightLineMeters > 0)
        j.transferWalk.straightLineMeters,
  ];
  out.writeln(
    'walking transfers among best journeys: ${walking.length}, straight '
    'line p50/max ${_p(walking, 50, 0)}/${_p(walking, 100, 0)} m',
  );
}

void _namedSection(
  StringBuffer out,
  BusNetwork network,
  Map<double, TransferIndex> indexes,
  List<Pair> named,
) {
  out
    ..writeln()
    ..writeln('Named fixtures (best journey per limit):');
  for (final p in named) {
    final plan = planDirectBus(network, p.origin, p.destination);
    out.writeln(
      '${p.label}: ${(haversineMeters(p.origin, p.destination) / 1000).toStringAsFixed(1)} km, '
      'direct plan ${_planName(plan)}, walking the whole way '
      '${_walkAll(p)} min',
    );
    if (plan is! NoDirectBus) continue;
    for (final walk in transferWalks) {
      // Limits with the same best journey share one line.
      final lines = <String, List<String>>{};
      for (final limit in detourLimits) {
        final r = searchOneTransfer(
          indexes[walk]!,
          p.origin,
          p.destination,
          detourLimit: limit,
        );
        final j = r.journeys.firstOrNull;
        final text = j == null
            ? 'none'
            : _describe(network, indexes[walk]!, p, j, label: false);
        (lines[text] ??= []).add(_limit(limit));
      }
      for (final MapEntry(key: text, value: limits) in lines.entries) {
        out.writeln('  ${_walkName(walk)}, ${limits.join('/')}: $text');
      }
    }
  }
}

List<Pair> _sample(BusNetwork network) {
  final codes = network.stops.keys.toList()..sort();
  final random = math.Random(seed);
  final pairs = <Pair>[];
  while (pairs.length < samplePairs) {
    final a = network.stops[codes[random.nextInt(codes.length)]]!;
    final b = network.stops[codes[random.nextInt(codes.length)]]!;
    if (haversineMeters(a.position, b.position) < minPairMeters) continue;
    pairs.add((
      label: '${a.code}->${b.code}',
      origin: _offset(a.position),
      destination: _offset(b.position),
    ));
  }
  return pairs;
}

LatLng _offset(LatLng p) =>
    LatLng(p.latitude + offsetDegrees, p.longitude + offsetDegrees);

int _band(Pair p) {
  final km = haversineMeters(p.origin, p.destination) / 1000;
  return km < 5
      ? 0
      : km < 10
      ? 1
      : km < 15
      ? 2
      : 3;
}

int _walkAll(Pair p) => WalkEstimate.between(p.origin, p.destination).minutes;

/// Walks + E2 rides, each rounded as E2 rounds; no wait. Null when E2 omits
/// a ride.
int? _estimate(BusNetwork network, TransferIndex index, TransferJourney j) {
  var total =
      j.walkToStop.minutes + j.transferWalk.minutes + j.walkFromStop.minutes;
  for (final ride in [j.first, j.second]) {
    final minutes = estimateBusMinutes(
      network,
      service: index.services[ride.service],
      direction: ride.direction,
      boardIndex: ride.from,
      stopCount: ride.to - ride.from,
    );
    if (minutes == null) return null;
    total += rideMinutesShown(minutes);
  }
  return total;
}

String _code(TransferIndex index, Ride ride, int at) =>
    index.services[ride.service].directions[ride.direction][at];

String _describe(
  BusNetwork network,
  TransferIndex index,
  Pair p,
  TransferJourney j, {
  bool label = true,
}) {
  final a = index.services[j.first.service].number;
  final b = index.services[j.second.service].number;
  final transfer = j.transferWalk.straightLineMeters == 0
      ? 'at ${_code(index, j.first, j.first.to)}'
      : '${_code(index, j.first, j.first.to)} -> '
            '${_code(index, j.second, j.second.from)} '
            '${j.transferWalk.straightLineMeters.round()} m';
  final est = _estimate(network, index, j);
  return '${label ? '${p.label} ' : ''}$a (${j.first.to - j.first.from} stops) + $b '
      '(${j.second.to - j.second.from} stops), change $transfer, '
      '${(haversineMeters(p.origin, p.destination) / 1000).toStringAsFixed(1)} km, '
      'detour ${j.detourRatio.toStringAsFixed(2)}, '
      'est. ${est ?? '-'} min excl. wait (${_speed(p, est)} km/h straight '
      'line), walking ${_walkAll(p)} min';
}

/// Straight-line origin-destination speed of an estimate, wait excluded.
String _speed(Pair p, int? minutes) => minutes == null || minutes == 0
    ? '-'
    : (haversineMeters(p.origin, p.destination) / 1000 / (minutes / 60))
          .toStringAsFixed(1);

/// Same text on the VM and dart2js (which prints 2.0 as 2).
String _limit(double? limit) => limit?.toStringAsFixed(1) ?? 'none';

/// `runtimeType` is minified by dart2js.
String _planName(JourneyPlan plan) => switch (plan) {
  WalkOnly() => 'walk only',
  DirectBusOptions() => 'direct bus',
  NoNearbyStops() => 'no nearby stops',
  NoDirectBus() => 'no direct bus',
};

String _walkName(double walk) => walk == 0 ? 'same stop' : '${walk.round()} m';

double _ms(Stopwatch w) => w.elapsedMicroseconds / 1000;

String _f(double v) => v.toStringAsFixed(2);

String _pc(int n, int of) =>
    '$n (${of == 0 ? '-' : (100 * n / of).toStringAsFixed(1)}%)';

/// Nearest-rank percentile; '-' for an empty list.
String _p(List<double> values, int percentile, [int digits = 2]) {
  if (values.isEmpty) return '-';
  final sorted = [...values]..sort();
  final rank = (percentile / 100 * sorted.length).ceil().clamp(
    1,
    sorted.length,
  );
  return sorted[rank - 1].toStringAsFixed(digits);
}

String _dist(List<double> ms) =>
    'median ${_p(ms, 50)} / p95 ${_p(ms, 95)} / max ${_p(ms, 100)} ms';
