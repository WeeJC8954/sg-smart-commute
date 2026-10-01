import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/core/geo/geo.dart';
import 'package:sg_smart_commute/features/environment/data/nea_parsers.dart';
import 'package:sg_smart_commute/features/environment/domain/environment_locator.dart';
import 'package:sg_smart_commute/features/environment/domain/environment_models.dart';

Object? fixture(String name) =>
    jsonDecode(File('test/fixtures/$name.json').readAsStringSync());

void main() {
  final fetchedAt = DateTime.utc(2026, 10, 1, 12, 13);
  final forecast = parseTwoHourForecast(
    fixture('two-hr-forecast'),
    fetchedAt: fetchedAt,
  );
  final pm25 = parsePm25(fixture('pm25'), fetchedAt: fetchedAt);
  final psi = parsePsi(fixture('psi'), fetchedAt: fetchedAt);
  final uv = parseUv(fixture('uv'), fetchedAt: fetchedAt);

  group('nearest forecast area', () {
    test('exact label location picks that area', () {
      final r = EnvironmentLocator.forecast(
        forecast,
        const LatLng(1.375, 103.839),
      );
      expect(r.scopeName, 'Ang Mo Kio');
      expect(r.scope, SpatialScope.area);
      expect(r.value, 'Cloudy');
      expect(r.observedAt, forecast.updatedAt);
      expect(r.fetchedAt, fetchedAt);
    });

    test('Bishan MRT resolves to the Bishan area', () {
      expect(
        EnvironmentLocator.forecast(
          forecast,
          const LatLng(1.3508, 103.8485),
        ).scopeName,
        'Bishan',
      );
    });

    test('VivoCity resolves to Bukit Merah (nearest label, ~1.4 km)', () {
      expect(
        EnvironmentLocator.forecast(
          forecast,
          const LatLng(1.2644, 103.8222),
        ).scopeName,
        'Bukit Merah',
      );
    });

    test(
      'an area without a forecast yields a null value (shown as unavailable)',
      () {
        final areas = [
          const ForecastArea(
            name: 'A',
            location: LatLng(1.3, 103.8),
            condition: null,
          ),
        ];
        final f = ForecastSnapshot(
          areas: areas,
          updatedAt: fetchedAt,
          validFrom: fetchedAt,
          validTo: fetchedAt,
          validText: '',
          fetchedAt: fetchedAt,
        );
        expect(
          EnvironmentLocator.forecast(f, const LatLng(1.3, 103.8)).value,
          isNull,
        );
      },
    );
  });

  group('nearest PM2.5 / PSI region', () {
    test('north, south, east, west, central', () {
      String region(double lat, double lng) =>
          EnvironmentLocator.regional(pm25, LatLng(lat, lng)).scopeName;
      expect(region(1.43, 103.79), 'north'); // Woodlands
      expect(region(1.27, 103.82), 'south'); // HarbourFront
      expect(region(1.35, 103.95), 'east'); // Tampines
      expect(region(1.34, 103.70), 'west'); // Jurong West
      expect(region(1.3508, 103.8485), 'central'); // Bishan
    });

    test(
      'PSI and PM2.5 use the same region rule but keep their own values',
      () {
        const bishan = LatLng(1.3508, 103.8485);
        final p = EnvironmentLocator.regional(pm25, bishan);
        final s = EnvironmentLocator.regional(psi, bishan);
        expect(p.scopeName, s.scopeName);
        expect(p.value, 35);
        expect(s.value, 75);
        expect(p.scope, SpatialScope.region);
        expect(s.observedAt, psi.observedAt);
      },
    );
  });

  test('UV is national', () {
    final r = EnvironmentLocator.uv(uv);
    expect(r.scope, SpatialScope.national);
    expect(r.scopeName, 'Singapore');
    expect(r.value, 0);
  });

  group('staleness', () {
    test('forecast is stale after 3 h', () {
      final r = EnvironmentLocator.forecast(
        forecast,
        const LatLng(1.375, 103.839),
      );
      expect(
        r.isStale(forecast.updatedAt.add(const Duration(hours: 3))),
        isFalse,
      );
      expect(
        r.isStale(forecast.updatedAt.add(const Duration(hours: 3, minutes: 1))),
        isTrue,
      );
    });

    test('PM2.5 / PSI are stale after 2 h', () {
      final r = EnvironmentLocator.regional(psi, const LatLng(1.3, 103.8));
      expect(r.isStale(psi.observedAt.add(const Duration(hours: 2))), isFalse);
      expect(
        r.isStale(psi.observedAt.add(const Duration(hours: 2, minutes: 1))),
        isTrue,
      );
    });

    test('clock skew (now before observedAt) is not stale', () {
      final r = EnvironmentLocator.regional(psi, const LatLng(1.3, 103.8));
      expect(
        r.isStale(psi.observedAt.subtract(const Duration(hours: 5))),
        isFalse,
      );
    });

    test('UV is stale after 2 h in daytime, never at night', () {
      final r = EnvironmentLocator.uv(uv); // observed 19:00 SGT
      // 21:30 SGT: night, so not stale.
      expect(r.isStale(DateTime.utc(2026, 10, 1, 13, 30)), isFalse);
      // 07:30 SGT next day: daytime, last reading 12.5 h old → stale.
      expect(r.isStale(DateTime.utc(2026, 10, 1, 23, 30)), isTrue);
    });

    test('isUvNight follows SGT hours', () {
      expect(isUvNight(DateTime.utc(2026, 10, 1, 12)), isTrue); // 20:00
      expect(isUvNight(DateTime.utc(2026, 10, 1, 11, 59)), isFalse); // 19:59
      expect(isUvNight(DateTime.utc(2026, 10, 1, 22, 59)), isTrue); // 06:59
      expect(isUvNight(DateTime.utc(2026, 10, 1, 23)), isFalse); // 07:00
    });
  });
}
