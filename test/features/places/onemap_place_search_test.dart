// OneMap parser and repository (guide v2.1 §8, §18 "Repository tests").
// All data is synthetic: the full response bodies come from
// test/fixtures/onemap/synthetic_onemap.dart (owner decisions A-4b, A-4c;
// README.md there lists the cases), and the rows built inline below are
// synthetic too.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/core/config/app_config.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sg_smart_commute/core/errors/app_failure.dart';
import 'package:sg_smart_commute/core/http/json_http_client.dart';
import 'package:sg_smart_commute/features/places/data/onemap_parser.dart';
import 'package:sg_smart_commute/features/places/data/onemap_place_search_repository.dart';
import 'package:sg_smart_commute/features/places/domain/place.dart';

import '../../fixtures/onemap/synthetic_onemap.dart';

const tokenMissing = syntheticTokenMessage;

/// A synthetic OneMap result row.
Map<String, String> row(
  String name, {
  String lat = '1.30',
  String lng = '103.83',
  String postal = 'NIL',
  String building = 'NIL',
  String block = '1',
  String address = 'NIL',
}) => {
  'SEARCHVAL': name,
  'BLK_NO': block,
  'ROAD_NAME': 'NIL',
  'BUILDING': building,
  'ADDRESS': address,
  'POSTAL': postal,
  'LATITUDE': lat,
  'LONGITUDE': lng,
};

String body(List<Map<String, String>> rows) => jsonEncode({
  'error': tokenMissing,
  'found': rows.length,
  'totalNumPages': 1,
  'pageNum': 1,
  'results': rows,
});

void main() {
  group('parseOneMapSearch (synthetic full bodies)', () {
    test('postal code: building name, address, postcode kept as a string', () {
      final places = parseOneMapSearch(jsonDecode(postalLeadingZeroBody));
      expect(places, hasLength(1));
      final p = places.single;
      expect(p.displayName, 'FAKE PLAZA (fake)');
      expect(p.postalCode, '009901'); // leading zero preserved
      expect(p.address, '1 FAKE ROAD FAKE PLAZA (fake) SINGAPORE 009901');
      expect(p.type, PlaceType.building);
      expect(p.source, PlaceSource.oneMap);
      expect(p.latitude, closeTo(1.221, 0.0001));
      expect(p.longitude, closeTo(103.731, 0.0001));
    });

    test('HDB block: an address (no building), exact block postcode', () {
      final places = parseOneMapSearch(jsonDecode(hdbBlockBody));
      expect(
        places.first.displayName,
        '901 FAKE ROAD 9 SINGAPORE 990901 (fake)',
      );
      expect(places.first.postalCode, '990901');
      expect(places.first.type, PlaceType.address);
      expect(places[1].postalCode, isNull); // "NIL"
    });

    test('MRT: typed as station; "NIL" postcode becomes null; codes kept', () {
      final places = parseOneMapSearch(jsonDecode(mrtStationBody));
      expect(places.first.type, PlaceType.mrtStation);
      expect(places.first.postalCode, isNull);
      expect(
        places.map((p) => p.displayName),
        containsAll([
          'FAKE MRT STATION (FK1) (fake)',
          'FAKE MRT STATION (FK2) (fake)',
        ]),
      );
      expect(places.last.displayName, 'FAKE LRT STATION (FL1) (fake)');
      expect(places.last.type, PlaceType.mrtStation);
    });

    test('street: several results, duplicates kept for the user to choose', () {
      final places = parseOneMapSearch(jsonDecode(streetBody));
      expect(places.length, greaterThan(1));
      final roads = places.where((p) => p.displayName == 'FAKE ROAD (fake)');
      expect(roads, hasLength(2));
      expect(roads.map((p) => p.type), [PlaceType.address, PlaceType.building]);
      // The provider's order is kept, and the row north of the SG box is
      // dropped.
      expect(places.map((p) => p.displayName), [
        'THE FAKE HOTEL ON FAKE ROAD (fake)',
        'FAKE ROAD (fake)',
        'FAKE ROAD (fake)',
        'FAKE ROAD - ERP(99) (fake)',
        'FAKE ROAD CHAPEL (fake)',
      ]);
    });

    test('mall: the mall and the station named after it are both offered', () {
      final names = parseOneMapSearch(jsonDecode(mallBody))
          .map((p) => p.displayName);
      expect(names, ['FAKE MALL (fake)', 'FAKE MALL STATION (FS1) (fake)']);
    });

    test('"error" + empty results (genuine no match, e.g. 000000) → []', () {
      expect(parseOneMapSearch(jsonDecode(postalNoMatchBody)), isEmpty);
      expect(parseOneMapSearch(jsonDecode(blockNoMatchBody)), isEmpty);
    });

    test('"error" + results is normal tokenless behaviour', () {
      final json = jsonDecode(tokenWithResultBody) as Map<String, dynamic>;
      expect(json['error'], isNotNull);
      expect(parseOneMapSearch(json), hasLength(1));
    });
  });

  group('parseOneMapSearch (synthetic edge cases)', () {
    test(
      'results outside Singapore or with invalid coordinates are dropped',
      () {
        final places = parseOneMapSearch(
          jsonDecode(
            body([
              row('IN SG'),
              row('LONDON', lat: '51.5', lng: '-0.12'),
              row('JOHOR BAHRU', lat: '1.49', lng: '103.76'),
              row('BAD LAT', lat: 'abc'),
              row('NIL LAT', lat: 'NIL'),
              row('NAN', lat: 'NaN'),
              row('NIL'), // no name
            ]),
          ),
        );
        expect(places.map((p) => p.displayName), ['IN SG']);
      },
    );

    test('a non-6-digit postcode is not kept as a postcode', () {
      final places = parseOneMapSearch(
        jsonDecode(body([row('X', postal: '12345')])),
      );
      expect(places.single.postalCode, isNull);
    });

    test('the name is SEARCHVAL, even when BUILDING and ADDRESS differ', () {
      final p = parseOneMapSearch(
        jsonDecode(
          body([row('NAME', building: 'OTHER BUILDING', address: 'ADDR')]),
        ),
      ).single;
      expect(p.displayName, 'NAME');
      expect(p.address, 'ADDR');
      expect(p.type, PlaceType.building);
    });

    test('an empty or blank field counts as missing, like "NIL"', () {
      final p = parseOneMapSearch(
        jsonDecode(body([row('ROAD', building: '', address: '  ')])),
      ).single;
      expect(p.address, isNull);
      expect(p.type, PlaceType.address);
    });

    test('malformed bodies → InvalidApiResponse', () {
      for (final bad in <Object?>[
        null,
        [1, 2],
        'text',
        {'found': 0},
        {'results': 'nope'},
      ]) {
        expect(
          () => parseOneMapSearch(bad),
          throwsA(isA<InvalidApiResponse>()),
          reason: '$bad',
        );
      }
    });

    test('"error" with no results field at all → ApiUnauthorized', () {
      expect(
        () => parseOneMapSearch({'error': tokenMissing}),
        throwsA(isA<ApiUnauthorized>()),
      );
    });

    test('only the first 10 results (page 1) are read (#59)', () {
      final places = parseOneMapSearch(
        jsonDecode(body([for (var i = 0; i < 11; i++) row('P$i')])),
      );
      expect(places.map((p) => p.displayName), [
        for (var i = 0; i < 10; i++) 'P$i',
      ]);
    });

    test('non-object rows are skipped', () {
      final places = parseOneMapSearch({
        'results': ['x', 42, row('OK')],
      });
      expect(places.single.displayName, 'OK');
    });
  });

  group('OneMapPlaceSearchRepository (mock HTTP)', () {
    late List<Uri> requests;
    late DateTime now;

    OneMapPlaceSearchRepository repo(
      FutureOr<http.Response> Function(http.Request) handler, {
      int maxCachedQueries = PlaceSearchConfig.maxCachedQueries,
    }) => OneMapPlaceSearchRepository(
      JsonHttpClient(
        MockClient((r) async {
          requests.add(r.url);
          return handler(r);
        }),
        timeout: const Duration(milliseconds: 50),
        delay: (_) async {},
      ),
      clock: () => now,
      maxCachedQueries: maxCachedQueries,
    );

    setUp(() {
      requests = [];
      now = DateTime.utc(2026, 10, 1, 12);
    });

    test('sends the normalised query to OneMap search', () async {
      final r = repo((_) => http.Response(hdbBlockBody, 200));
      await r.search('  Blk 901   Fake Road 9 ', mode: SearchMode.submit);
      final uri = requests.single;
      expect(uri.host, 'www.onemap.gov.sg');
      expect(uri.path, '/api/common/elastic/search');
      expect(uri.queryParameters['searchVal'], '901 Fake Road 9');
      expect(uri.queryParameters['returnGeom'], 'Y');
      expect(uri.queryParameters['getAddrDetails'], 'Y');
    });

    test(
      'leading-zero postal code: exact match kept, string compared',
      () async {
        final r = repo((_) => http.Response(postalLeadingZeroBody, 200));
        final places = await r.search('009901', mode: SearchMode.typeahead);
        expect(places.single.postalCode, '009901');
      },
    );

    test('6-digit query keeps only the exact postcode among several', () async {
      final r = repo(
        (_) => http.Response(
          body([
            row('NEAR MISS', postal: '640517'),
            row('EXACT', postal: '640512'),
            row('NO CODE'),
          ]),
          200,
        ),
      );
      final places = await r.search('640512', mode: SearchMode.submit);
      expect(places.map((p) => p.displayName), ['EXACT']);
    });

    test(
      '6-digit query with only fuzzy matches → NoExactPostalMatch',
      () async {
        final r = repo(
          (_) => http.Response(body([row('NEAR MISS', postal: '640517')]), 200),
        );
        await expectLater(
          r.search('640512', mode: SearchMode.submit),
          throwsA(
            isA<NoExactPostalMatch>().having(
              (e) => e.postalCode,
              'code',
              '640512',
            ),
          ),
        );
      },
    );

    test('a postal code with no results at all → [] (no match)', () async {
      final r = repo((_) => http.Response(postalNoMatchBody, 200));
      expect(await r.search('000000', mode: SearchMode.submit), isEmpty);
    });

    test('a non-postal query is not postcode-filtered', () async {
      final r = repo((_) => http.Response(mallBody, 200));
      expect(
        await r.search('Fake Mall', mode: SearchMode.submit),
        hasLength(2),
      );
    });

    test('401 and 403 (token enforcement) → ApiUnauthorized', () async {
      for (final status in [401, 403]) {
        final r = repo(
          (_) => http.Response('{"message":"Unauthorized"}', status),
        );
        await expectLater(
          r.search('Fake Mall', mode: SearchMode.submit),
          throwsA(isA<ApiUnauthorized>()),
          reason: 'HTTP $status',
        );
      }
    });

    test('timeout and network failure → NetworkUnavailable', () async {
      final slow = repo((_) async {
        await Future<void>.delayed(const Duration(seconds: 1));
        return http.Response(mallBody, 200);
      });
      await expectLater(
        slow.search('Fake Mall', mode: SearchMode.submit),
        throwsA(isA<NetworkUnavailable>()),
      );
      final offline = repo((_) => throw http.ClientException('offline'));
      await expectLater(
        offline.search('Fake Mall', mode: SearchMode.submit),
        throwsA(isA<NetworkUnavailable>()),
      );
    });

    test('malformed response → InvalidApiResponse', () async {
      for (final text in ['<html>', '{"results": 3}', '[]']) {
        final r = repo((_) => http.Response(text, 200));
        await expectLater(
          r.search('Fake Mall', mode: SearchMode.submit),
          throwsA(isA<InvalidApiResponse>()),
          reason: text,
        );
      }
    });

    test('short queries make no request', () async {
      final r = repo((_) => http.Response(mallBody, 200));
      expect(await r.search('vi', mode: SearchMode.typeahead), isEmpty);
      expect(await r.search('   ', mode: SearchMode.submit), isEmpty);
      expect(requests, isEmpty);
    });

    test(
      'results are cached per normalised query for 5 min; then refetched',
      () async {
        final r = repo((_) => http.Response(mallBody, 200));
        await r.search('Fake Mall', mode: SearchMode.typeahead);
        await r.search('  Fake Mall ', mode: SearchMode.submit);
        expect(requests, hasLength(1));
        now = now.add(const Duration(minutes: 5));
        await r.search('Fake Mall', mode: SearchMode.submit);
        expect(requests, hasLength(2));
      },
    );

    test('a pasted multi-KB query is cut before it is sent', () async {
      final r = repo((_) => http.Response(mallBody, 200));
      await r.search('Fake Mall ${'x' * 5000}', mode: SearchMode.submit);
      final sent = requests.single.queryParameters['searchVal']!;
      expect(sent.length, PlaceSearchConfig.maxQueryLength);
      expect(sent, startsWith('Fake Mall x'));
    });

    test('the cache holds at most maxCachedQueries, evicting the least '
        'recently used', () async {
      final r = repo((_) => http.Response(mallBody, 200), maxCachedQueries: 2);
      await r.search('aaa', mode: SearchMode.submit);
      await r.search('bbb', mode: SearchMode.submit);
      await r.search('aaa', mode: SearchMode.submit); // hit: aaa is recent
      expect(requests, hasLength(2));
      await r.search('ccc', mode: SearchMode.submit); // evicts bbb
      expect(r.cachedQueryCount, 2);
      await r.search('aaa', mode: SearchMode.submit); // still cached
      expect(requests, hasLength(3));
      await r.search('bbb', mode: SearchMode.submit); // evicted: refetched
      expect(requests, hasLength(4));
    });

    test('expired entries are dropped when a new one is written', () async {
      final r = repo((_) => http.Response(mallBody, 200));
      for (final q in ['aaa', 'bbb', 'ccc']) {
        await r.search(q, mode: SearchMode.typeahead);
      }
      expect(r.cachedQueryCount, 3);
      now = now.add(PlaceSearchConfig.cacheTtl);
      await r.search('ddd', mode: SearchMode.typeahead);
      expect(r.cachedQueryCount, 1);
    });

    test('failures are not cached', () async {
      var fail = true;
      final r = repo(
        (_) => fail ? http.Response('down', 400) : http.Response(mallBody, 200),
      );
      await expectLater(
        r.search('Fake Mall', mode: SearchMode.submit),
        throwsA(isA<ApiUnavailable>()),
      );
      fail = false;
      expect(
        await r.search('Fake Mall', mode: SearchMode.submit),
        hasLength(2),
      );
    });

    test(
      'reverseGeocode → null without any request (OneMap needs a token)',
      () async {
        final r = repo((_) => http.Response('{}', 200));
        expect(await r.reverseGeocode(1.284, 103.851), isNull);
        expect(requests, isEmpty);
      },
    );
  });
}
