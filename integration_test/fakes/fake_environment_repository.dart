import 'dart:async';

import 'package:sg_smart_commute/core/errors/app_failure.dart';
import 'package:sg_smart_commute/core/geo/geo.dart';
import 'package:sg_smart_commute/features/environment/domain/environment_models.dart';
import 'package:sg_smart_commute/features/environment/domain/environment_repository.dart';

/// Fixed instant used by widget and integration tests: 12:12 SGT.
final fakeNow = DateTime.utc(2026, 10, 1, 4, 12);

/// Deterministic [EnvironmentRepository]: fixed domain objects, no HTTP.
///
/// Set a `fail*` field to make that dataset throw; clear it to "recover".
/// Set [gate] to hold every request until it completes (a slow network).
class FakeEnvironmentRepository implements EnvironmentRepository {
  AppFailure? failForecast;
  AppFailure? failUv;
  AppFailure? failPm25;
  AppFailure? failPsi;

  Completer<void>? gate;

  final Map<String, int> calls = {};

  Future<void> _count(String k) async {
    calls[k] = (calls[k] ?? 0) + 1;
    await gate?.future;
  }

  @override
  Future<ForecastSnapshot> twoHourForecast() async {
    await _count('forecast');
    if (failForecast != null) throw failForecast!;
    return fakeForecast;
  }

  @override
  Future<UvSnapshot> uv() async {
    await _count('uv');
    if (failUv != null) throw failUv!;
    return fakeUv;
  }

  @override
  Future<RegionalSnapshot> pm25OneHour() async {
    await _count('pm25');
    if (failPm25 != null) throw failPm25!;
    return fakePm25;
  }

  @override
  Future<RegionalSnapshot> psiTwentyFourHour() async {
    await _count('psi');
    if (failPsi != null) throw failPsi!;
    return fakePsi;
  }
}

final _observed = DateTime.utc(2026, 10, 1, 4); // 12:00 SGT

final fakeForecast = ForecastSnapshot(
  areas: const [
    ForecastArea(
      name: 'Bishan',
      location: LatLng(1.350772, 103.839),
      condition: 'Partly Cloudy (Day)',
    ),
    ForecastArea(
      name: 'Tampines',
      location: LatLng(1.345909, 103.944),
      condition: 'Thundery Showers',
    ),
    ForecastArea(
      name: 'Jurong East',
      location: LatLng(1.326, 103.737),
      condition: 'Light Rain',
    ),
  ],
  updatedAt: _observed.add(const Duration(minutes: 5)),
  validFrom: _observed,
  validTo: _observed.add(const Duration(hours: 2)),
  validText: '12.00 pm to 2.00 pm',
  fetchedAt: fakeNow,
);

final fakeUv = UvSnapshot(
  value: 7,
  observedAt: _observed,
  updatedAt: _observed.add(const Duration(minutes: 10)),
  fetchedAt: fakeNow,
);

const _regions = {
  'north': LatLng(1.41803, 103.82),
  'south': LatLng(1.29587, 103.82),
  'east': LatLng(1.35735, 103.94),
  'west': LatLng(1.35735, 103.7),
  'central': LatLng(1.35735, 103.82),
};

final fakePm25 = RegionalSnapshot(
  metric: AirMetric.pm25OneHour,
  regions: _regions,
  values: const {
    'north': 11,
    'south': 12,
    'east': 13,
    'west': 14,
    'central': 18,
  },
  observedAt: _observed,
  updatedAt: _observed,
  fetchedAt: fakeNow,
);

final fakePsi = RegionalSnapshot(
  metric: AirMetric.psiTwentyFourHour,
  regions: _regions,
  values: const {
    'north': 51,
    'south': 52,
    'east': 61,
    'west': 53,
    'central': 54,
  },
  observedAt: _observed,
  updatedAt: _observed,
  fetchedAt: fakeNow,
);
