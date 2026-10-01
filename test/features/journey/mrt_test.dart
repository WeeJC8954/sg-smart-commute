// MRT exit → station grouping, the bundled asset, and the nearest station
// (guide v2.1 §9.5).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/core/errors/app_failure.dart';
import 'package:sg_smart_commute/core/geo/geo.dart';
import 'package:sg_smart_commute/features/journey/data/mrt_asset.dart';
import 'package:sg_smart_commute/features/journey/data/mrt_asset_repository.dart';
import 'package:sg_smart_commute/features/journey/data/mrt_grouping.dart';
import 'package:sg_smart_commute/features/journey/domain/mrt.dart';

RawMrtExit raw(String name, String exit, double lat, double lng) => RawMrtExit(
  stationName: name,
  exitCode: exit,
  latitude: lat,
  longitude: lng,
);

final Map<String, dynamic> bundled = jsonDecode(
  File('assets/mrt_stations.json').readAsStringSync(),
) as Map<String, dynamic>;

void main() {
  group('grouping exits into stations', () {
    test('exits of one station become one station, never several', () {
      final r = groupMrtExits([
        raw('BISHAN MRT STATION', 'Exit A', 1.3510, 103.8502),
        raw('BISHAN MRT STATION', 'Exit B', 1.3506, 103.8483),
        raw('BISHAN MRT STATION', 'Exit C', 1.3511, 103.8483),
        raw('ANG MO KIO MRT STATION', 'Exit A', 1.3700, 103.8495),
      ]);
      expect(r.stations.map((s) => s.name), [
        'ANG MO KIO MRT STATION',
        'BISHAN MRT STATION',
      ]);
      expect(r.stations[1].exits.map((e) => e.code), [
        'Exit A',
        'Exit B',
        'Exit C',
      ]);
    });

    test('identical duplicate records are dropped', () {
      final r = groupMrtExits([
        raw('X MRT STATION', 'Exit A', 1.3, 103.8),
        raw('X MRT STATION', 'Exit A', 1.3, 103.8),
      ]);
      expect(r.stations.single.exits, hasLength(1));
      expect(r.duplicateExits, 1);
    });

    test('a verified code-only record joins the named station', () {
      final r = groupMrtExits([
        raw('PAYA LEBAR MRT STATION', 'Exit A', 1.3177, 103.8925),
        raw('CC9', 'E', 1.3181, 103.8929),
      ]);
      expect(r.stations.single.name, 'PAYA LEBAR MRT STATION');
      expect(r.stations.single.exits, hasLength(2));
      expect(r.mappedCodeOnly, ['CC9']);
      expect(r.unverifiedCodeOnly, isEmpty);
    });

    test('an unverified code-only record stays a separate code-labelled '
        'station, even right next to a named one', () {
      final r = groupMrtExits([
        raw('PAYA LEBAR MRT STATION', 'Exit A', 1.3177, 103.8925),
        raw('ZZ99', '1', 1.3178, 103.8926), // ~15 m away, but not verified
      ]);
      expect(r.stations.map((s) => s.name), ['PAYA LEBAR MRT STATION', 'ZZ99']);
      expect(r.unverifiedCodeOnly, ['ZZ99']);
    });

    test('the mapping applies only to the exact code', () {
      expect(isCodeOnlyStationName('CC9'), isTrue);
      expect(isCodeOnlyStationName('NE18'), isTrue);
      expect(isCodeOnlyStationName('CC9 MRT STATION'), isFalse);
      expect(isCodeOnlyStationName('BISHAN MRT STATION'), isFalse);
      final r = groupMrtExits([
        raw('CC9', 'E', 1.3181, 103.8929),
      ], codeOnly: const []);
      expect(r.stations.single.name, 'CC9'); // no mapping → kept as is
    });

    test('deterministic: input order does not change the output', () {
      final exits = [
        raw('B MRT STATION', 'Exit B', 1.31, 103.81),
        raw('A MRT STATION', 'Exit A', 1.30, 103.80),
        raw('B MRT STATION', 'Exit A', 1.32, 103.82),
      ];
      String encode(List<RawMrtExit> e) =>
          jsonEncode(encodeMrtStations(groupMrtExits(e).stations));
      expect(encode(exits), encode(exits.reversed.toList()));
    });
  });

  group('the bundled asset (assets/mrt_stations.json)', () {
    test('records its source, licence and validation counts', () {
      final source = bundled['source'] as Map<String, dynamic>;
      expect(source['datasetId'], 'd_b39d3a0871985372d7e1637193335da5');
      expect(source['licence'], 'Singapore Open Data Licence v1.0');
      expect(source['retrieved'], isNotEmpty);
      final counts = bundled['counts'] as Map<String, dynamic>;
      expect(counts['features'], 613);
      expect(counts['exits'], 613);
      expect(counts['stations'], 188);
      expect(counts['codeOnlyMapped'], 7);
      expect(counts['codeOnlyUnverified'], 0);
    });

    test('parses; every station appears once; no code-only names remain', () {
      final stations = parseMrtAsset(bundled);
      final names = stations.map((s) => s.name).toList();
      expect(names, hasLength(188));
      expect(names.toSet(), hasLength(188));
      expect(names.where(isCodeOnlyStationName), isEmpty);
      expect(names, containsAll(['HUME MRT STATION', 'KEPPEL MRT STATION']));
      final payaLebar = stations.firstWhere(
        (s) => s.name == 'PAYA LEBAR MRT STATION',
      );
      expect(payaLebar.exits.map((e) => e.code), containsAll(['E', 'F']));
    });

    test(
      'the generator would reproduce it: grouping its own exits is a no-op',
      () {
        final stations = parseMrtAsset(bundled);
        final regrouped = groupMrtExits([
          for (final s in stations)
            for (final e in s.exits)
              raw(s.name, e.code, e.position.latitude, e.position.longitude),
        ]);
        expect(
          jsonEncode(encodeMrtStations(regrouped.stations)),
          jsonEncode(bundled['stations']),
        );
      },
    );

    test('malformed asset → StaticDataUnavailable', () async {
      Matcher bad() => throwsA(isA<StaticDataUnavailable>());
      expect(() => parseMrtAsset([1]), bad());
      expect(() => parseMrtAsset({'stations': []}), bad());
      expect(
        () => parseMrtAsset({
          'stations': [
            {'name': 'X', 'exits': []},
          ],
        }),
        bad(),
      );
      expect(
        () => parseMrtAsset({
          'stations': [
            {
              'name': 'X',
              'exits': [
                {'exit': 'A', 'lat': 103.8, 'lng': 1.3}, // swapped
              ],
            },
          ],
        }),
        bad(),
      );
      await expectLater(
        MrtAssetRepository(load: () async => '<html>').stations(),
        bad(),
      );
      await expectLater(
        MrtAssetRepository(load: () => throw Exception('missing')).stations(),
        bad(),
      );
    });

    test('repository loads once per session; a failure is retried', () async {
      var loads = 0;
      var fail = true;
      final repo = MrtAssetRepository(
        load: () async {
          loads++;
          if (fail) throw Exception('not yet');
          return jsonEncode(bundled);
        },
      );
      await expectLater(repo.stations(), throwsA(isA<StaticDataUnavailable>()));
      fail = false;
      final a = await repo.stations();
      final b = await repo.stations();
      expect(identical(a, b), isTrue);
      expect(loads, 2);
    });
  });

  group('nearest MRT station', () {
    final stations = parseMrtAsset(bundled);

    test('Bishan: nearest by exit, with an estimated walk', () {
      final s = nearestMrtStation(stations, const LatLng(1.3520, 103.8500))!;
      expect(s.station.name, 'BISHAN MRT STATION');
      expect(s.walk.minutes, greaterThan(0));
      expect(s.walk.label, endsWith('min walk (est.)'));
    });

    test('measured to the nearest exit, not a centre point', () {
      // Two exits 1 km apart; the point sits 100 m from one of them.
      const far = MrtStation(
        name: 'LONG MRT STATION',
        exits: [
          MrtExit(code: 'Exit A', position: LatLng(1.3000, 103.8000)),
          MrtExit(code: 'Exit B', position: LatLng(1.3090, 103.8000)),
        ],
      );
      const near = MrtStation(
        name: 'MID MRT STATION',
        exits: [MrtExit(code: 'Exit A', position: LatLng(1.3060, 103.8000))],
      );
      final s = nearestMrtStation(const [
        far,
        near,
      ], const LatLng(1.3081, 103.8000))!;
      expect(s.station.name, 'LONG MRT STATION'); // Exit B is 100 m away
      expect(s.nearestExit.code, 'Exit B');
    });

    test('nothing within 1.5 km → null; ties go to the name', () {
      expect(
        nearestMrtStation(stations, const LatLng(1.2700, 104.0500)),
        isNull,
      );
      const a = MrtStation(
        name: 'A MRT STATION',
        exits: [MrtExit(code: '1', position: LatLng(1.30, 103.81))],
      );
      const b = MrtStation(
        name: 'B MRT STATION',
        exits: [MrtExit(code: '1', position: LatLng(1.30, 103.81))],
      );
      expect(
        nearestMrtStation(const [
          b,
          a,
        ], const LatLng(1.30, 103.80))!.station.name,
        'A MRT STATION',
      );
    });
  });
}
