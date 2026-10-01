// Parser tests run against real data.gov.sg payloads captured on 2026-10-01
// (test/fixtures/*.json, fetched once with curl; see docs/testing.md).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/core/errors/app_failure.dart';
import 'package:sg_smart_commute/features/environment/data/nea_parsers.dart';
import 'package:sg_smart_commute/features/environment/domain/environment_models.dart';

Object? fixture(String name) =>
    jsonDecode(File('test/fixtures/$name.json').readAsStringSync());

void main() {
  final fetchedAt = DateTime.utc(2026, 10, 1, 12, 13);

  group('parseTwoHourForecast', () {
    test('maps all 47 areas with their label locations and forecasts', () {
      final f = parseTwoHourForecast(
        fixture('two-hr-forecast'),
        fetchedAt: fetchedAt,
      );
      expect(f.areas, hasLength(47));
      final amk = f.areas.firstWhere((a) => a.name == 'Ang Mo Kio');
      expect(amk.location.latitude, 1.375);
      expect(amk.location.longitude, 103.839);
      expect(amk.condition, 'Cloudy');
      expect(f.updatedAt, DateTime.utc(2026, 10, 1, 12, 6, 33));
      expect(f.validFrom, DateTime.utc(2026, 10, 1, 12));
      expect(f.validTo, DateTime.utc(2026, 10, 1, 14));
      expect(f.validText, '8.00 pm to 10.00 pm');
      expect(f.fetchedAt, fetchedAt);
    });

    test('an area without a forecast entry keeps a null condition', () {
      final json = fixture('two-hr-forecast') as Map<String, dynamic>;
      final items =
          (json['data']['items'] as List).first as Map<String, dynamic>;
      (items['forecasts'] as List).removeWhere((f) => f['area'] == 'Bishan');
      final f = parseTwoHourForecast(json, fetchedAt: fetchedAt);
      expect(f.areas.firstWhere((a) => a.name == 'Bishan').condition, isNull);
    });

    test('malformed payloads throw InvalidApiResponse', () {
      expect(
        () => parseTwoHourForecast({'code': 0}, fetchedAt: fetchedAt),
        throwsA(isA<InvalidApiResponse>()),
      );
      expect(
        () => parseTwoHourForecast('nope', fetchedAt: fetchedAt),
        throwsA(isA<InvalidApiResponse>()),
      );
      expect(
        () => parseTwoHourForecast({
          'code': 0,
          'data': {'area_metadata': [], 'items': []},
        }, fetchedAt: fetchedAt),
        throwsA(isA<InvalidApiResponse>()),
      );
    });

    test('non-zero code throws ApiUnavailable', () {
      expect(
        () => parseTwoHourForecast({
          'code': 17,
          'errorMsg': 'x',
          'data': null,
        }, fetchedAt: fetchedAt),
        throwsA(isA<ApiUnavailable>()),
      );
    });
  });

  group('parseUv', () {
    test('takes the latest hourly index entry regardless of order', () {
      final uv = parseUv(fixture('uv'), fetchedAt: fetchedAt);
      expect(uv.value, 0);
      expect(uv.observedAt, DateTime.utc(2026, 10, 1, 11)); // 19:00 SGT
      expect(uv.updatedAt, DateTime.utc(2026, 10, 1, 11, 11, 17));
    });

    test('order-independent: reversed index still yields the latest hour', () {
      final json = fixture('uv') as Map<String, dynamic>;
      final rec = (json['data']['records'] as List).first;
      rec['index'] = (rec['index'] as List).reversed.toList();
      expect(
        parseUv(json, fetchedAt: fetchedAt).observedAt,
        DateTime.utc(2026, 10, 1, 11),
      );
    });

    test('empty index throws InvalidApiResponse', () {
      final json = fixture('uv') as Map<String, dynamic>;
      (json['data']['records'] as List).first['index'] = [];
      expect(
        () => parseUv(json, fetchedAt: fetchedAt),
        throwsA(isA<InvalidApiResponse>()),
      );
    });
  });

  group('parsePm25 / parsePsi — never confused', () {
    test('PM2.5 uses pm25_one_hourly', () {
      final r = parsePm25(fixture('pm25'), fetchedAt: fetchedAt);
      expect(r.metric, AirMetric.pm25OneHour);
      expect(
        r.regions.keys,
        containsAll(['north', 'south', 'east', 'west', 'central']),
      );
      expect(r.values['central'], 35);
      expect(r.values['north'], 18);
      expect(r.observedAt, DateTime.utc(2026, 10, 1, 12));
      expect(r.updatedAt, DateTime.utc(2026, 10, 1, 12, 1, 33));
    });

    test('PSI uses psi_twenty_four_hourly, not pm25_twenty_four_hourly or a sub-index', () {
      final r = parsePsi(fixture('psi'), fetchedAt: fetchedAt);
      expect(r.metric, AirMetric.psiTwentyFourHour);
      expect(r.values['central'], 75); // psi_twenty_four_hourly
      expect(r.values['central'], isNot(33)); // pm25_twenty_four_hourly
      expect(r.values['north'], 60);
    });

    test('PSI payload without psi_twenty_four_hourly is rejected (no substitution)', () {
      final json = fixture('psi') as Map<String, dynamic>;
      final readings =
          ((json['data']['items'] as List).first)['readings']
              as Map<String, dynamic>;
      readings.remove('psi_twenty_four_hourly');
      expect(
        () => parsePsi(json, fetchedAt: fetchedAt),
        throwsA(isA<InvalidApiResponse>()),
      );
    });

    test('a PSI payload fed to the PM2.5 parser is rejected', () {
      expect(
        () => parsePm25(fixture('psi'), fetchedAt: fetchedAt),
        throwsA(isA<InvalidApiResponse>()),
      );
    });

    test(
      'regionMetadata "national" entries are kept out of the region map',
      () {
        final json = fixture('pm25') as Map<String, dynamic>;
        (json['data']['regionMetadata'] as List).add({
          'name': 'national',
          'labelLocation': {'latitude': 0, 'longitude': 0},
        });
        final r = parsePm25(json, fetchedAt: fetchedAt);
        expect(r.regions.containsKey('national'), isFalse);
      },
    );
  });
}
