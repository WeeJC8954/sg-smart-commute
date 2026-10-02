// OneMap parser and repository (guide v2.1 §8, §18 "Repository tests").
// Fixtures in test/fixtures/onemap/ are real tokenless responses captured with
// curl on 2026-10-01. Payloads built inline are synthetic and say so.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/core/config/app_config.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sg_smart_commute/core/errors/app_failure.dart';
import 'package:sg_smart_commute/core/http/json_http_client.dart';
import 'package:sg_smart_commute/features/places/data/onemap_parser.dart';
import 'package:sg_smart_commute/features/places/data/onemap_place_search_repository.dart';
import 'package:sg_smart_commute/features/places/domain/place.dart';

Object? fixture(String name) =>
    jsonDecode(File('test/fixtures/onemap/$name.json').readAsStringSync());

String fixtureBody(String name) =>
    File('test/fixtures/onemap/$name.json').readAsStringSync();

const tokenMissing =
    'Authentication token missing. Please create an account and generate or '
    'renew your API Token.';

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
  group('parseOneMapSearch (real fixtures)', () {
    test('postal code: building name, address, postcode kept as a string', () {
      final places = parseOneMapSearch(fixture('postal-098585'));
      expect(places, hasLength(1));
      final p = places.single;
      expect(p.displayName, 'VIVOCITY');
      expect(p.postalCode, '098585'); // leading zero preserved
      expect(p.address, '1 HARBOURFRONT WALK VIVOCITY SINGAPORE 098585');
      expect(p.type, PlaceType.building);
      expect(p.source, PlaceSource.oneMap);
      expect(p.latitude, closeTo(1.2642, 0.001));
      expect(p.longitude, closeTo(103.8223, 0.001));
    });

    test('HDB block: an address (no building), exact block postcode', () {
      final places = parseOneMapSearch(fixture('hdb-123-amk-ave-6'));
      expect(
        places.first.displayName,
        '123 ANG MO KIO AVENUE 6 SINGAPORE 560123',
      );
      expect(places.first.postalCode, '560123');
      expect(places.first.type, PlaceType.address);
      expect(places[1].postalCode, isNull); // "NIL"
    });

    test('MRT: typed as station; "NIL" postcode becomes null; codes kept', () {
      final places = parseOneMapSearch(fixture('mrt-bishan'));
      expect(places.first.type, PlaceType.mrtStation);
      expect(places.first.postalCode, isNull);
      expect(
        places.map((p) => p.displayName),
        containsAll(['BISHAN MRT STATION (CC15)', 'BISHAN MRT STATION (NS17)']),
      );
    });

    test('street: several results, duplicates kept for the user to choose', () {
      final places = parseOneMapSearch(fixture('street-orchard-road'));
      expect(places.length, greaterThan(1));
      expect(
        places.where((p) => p.displayName == 'ORCHARD ROAD'),
        hasLength(2),
      );
    });

    test('mall: VivoCity and VivoCity station are both offered', () {
      final names = parseOneMapSearch(fixture('mall-vivocity'))
          .map((p) => p.displayName);
      expect(names, ['VIVOCITY', 'VIVOCITY STATION (S1)']);
    });

    test('"error" + empty results (genuine no match, e.g. 000000) → []', () {
      expect(parseOneMapSearch(fixture('postal-000000')), isEmpty);
      expect(parseOneMapSearch(fixture('hdb-blk-raw')), isEmpty);
    });

    test('"error" + results is normal tokenless behaviour', () {
      expect(parseOneMapSearch(fixture('postal-238801')), hasLength(1));
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
      final r = repo(
        (_) => http.Response(fixtureBody('hdb-123-amk-ave-6'), 200),
      );
      await r.search('  Blk 123   Ang Mo Kio Ave 6 ', mode: SearchMode.submit);
      final uri = requests.single;
      expect(uri.host, 'www.onemap.gov.sg');
      expect(uri.path, '/api/common/elastic/search');
      expect(uri.queryParameters['searchVal'], '123 Ang Mo Kio Ave 6');
      expect(uri.queryParameters['returnGeom'], 'Y');
      expect(uri.queryParameters['getAddrDetails'], 'Y');
    });

    test(
      'leading-zero postal code: exact match kept, string compared',
      () async {
        final r = repo((_) => http.Response(fixtureBody('postal-098585'), 200));
        final places = await r.search('098585', mode: SearchMode.typeahead);
        expect(places.single.postalCode, '098585');
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
      final r = repo((_) => http.Response(fixtureBody('postal-000000'), 200));
      expect(await r.search('000000', mode: SearchMode.submit), isEmpty);
    });

    test('a non-postal query is not postcode-filtered', () async {
      final r = repo((_) => http.Response(fixtureBody('mall-vivocity'), 200));
      expect(await r.search('VivoCity', mode: SearchMode.submit), hasLength(2));
    });

    test('401 and 403 (token enforcement) → ApiUnauthorized', () async {
      for (final status in [401, 403]) {
        final r = repo(
          (_) => http.Response('{"message":"Unauthorized"}', status),
        );
        await expectLater(
          r.search('VivoCity', mode: SearchMode.submit),
          throwsA(isA<ApiUnauthorized>()),
          reason: 'HTTP $status',
        );
      }
    });

    test('timeout and network failure → NetworkUnavailable', () async {
      final slow = repo((_) async {
        await Future<void>.delayed(const Duration(seconds: 1));
        return http.Response(fixtureBody('mall-vivocity'), 200);
      });
      await expectLater(
        slow.search('VivoCity', mode: SearchMode.submit),
        throwsA(isA<NetworkUnavailable>()),
      );
      final offline = repo((_) => throw http.ClientException('offline'));
      await expectLater(
        offline.search('VivoCity', mode: SearchMode.submit),
        throwsA(isA<NetworkUnavailable>()),
      );
    });

    test('malformed response → InvalidApiResponse', () async {
      for (final text in ['<html>', '{"results": 3}', '[]']) {
        final r = repo((_) => http.Response(text, 200));
        await expectLater(
          r.search('VivoCity', mode: SearchMode.submit),
          throwsA(isA<InvalidApiResponse>()),
          reason: text,
        );
      }
    });

    test('short queries make no request', () async {
      final r = repo((_) => http.Response(fixtureBody('mall-vivocity'), 200));
      expect(await r.search('vi', mode: SearchMode.typeahead), isEmpty);
      expect(await r.search('   ', mode: SearchMode.submit), isEmpty);
      expect(requests, isEmpty);
    });

    test(
      'results are cached per normalised query for 5 min; then refetched',
      () async {
        final r = repo((_) => http.Response(fixtureBody('mall-vivocity'), 200));
        await r.search('VivoCity', mode: SearchMode.typeahead);
        await r.search('  VivoCity ', mode: SearchMode.submit);
        expect(requests, hasLength(1));
        now = now.add(const Duration(minutes: 5));
        await r.search('VivoCity', mode: SearchMode.submit);
        expect(requests, hasLength(2));
      },
    );

    test('a pasted multi-KB query is cut before it is sent', () async {
      final r = repo((_) => http.Response(fixtureBody('mall-vivocity'), 200));
      await r.search('VivoCity ${'x' * 5000}', mode: SearchMode.submit);
      final sent = requests.single.queryParameters['searchVal']!;
      expect(sent.length, PlaceSearchConfig.maxQueryLength);
      expect(sent, startsWith('VivoCity x'));
    });

    test('the cache holds at most maxCachedQueries, evicting the least '
        'recently used', () async {
      final r = repo(
        (_) => http.Response(fixtureBody('mall-vivocity'), 200),
        maxCachedQueries: 2,
      );
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
      final r = repo((_) => http.Response(fixtureBody('mall-vivocity'), 200));
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
        (_) => fail
            ? http.Response('down', 400)
            : http.Response(fixtureBody('mall-vivocity'), 200),
      );
      await expectLater(
        r.search('VivoCity', mode: SearchMode.submit),
        throwsA(isA<ApiUnavailable>()),
      );
      fail = false;
      expect(await r.search('VivoCity', mode: SearchMode.submit), hasLength(2));
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
