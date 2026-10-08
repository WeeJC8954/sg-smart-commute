// busrouter routes.min.json parsing and the repository. The fixture in
// test/fixtures/busrouter/geometry/routes.json is an unmodified subset of the
// live file: services 10 and 46 (two directions), 4, 11, 2B and 115 (one).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sg_smart_commute/core/config/app_config.dart';
import 'package:sg_smart_commute/core/errors/app_failure.dart';
import 'package:sg_smart_commute/core/http/json_http_client.dart';
import 'package:sg_smart_commute/features/map/data/busrouter_route_geometry_repository.dart';
import 'package:sg_smart_commute/features/map/data/busrouter_routes_parser.dart';
import 'package:sg_smart_commute/features/map/map_providers.dart';
import 'package:sg_smart_commute/main.dart' show noAutomaticRetry;

final String routesBody = File('test/fixtures/busrouter/geometry/routes.json')
    .readAsStringSync();

Matcher unavailable() => throwsA(
  isA<StaticDataUnavailable>().having(
    (e) => e.dataset,
    'dataset',
    StaticDataset.busRouteGeometry,
  ),
);

void main() {
  group('parseBusrouterRoutes', () {
    test('the captured fixture parses without decoding', () {
      final geometry = parseBusrouterRoutes(jsonDecode(routesBody));
      expect(geometry.serviceCount, 6);
      expect(geometry.encoded('10', 0), isNotNull);
      expect(geometry.encoded('10', 1), isNotNull);
      expect(geometry.encoded('10', 2), isNull);
      expect(geometry.encoded('4', 1), isNull);
      expect(geometry.encoded('nope', 0), isNull);
    });

    Map<String, Object?> good(int n) => {
      for (var i = 0; i < n; i++) 'S$i': ['abc$i'],
    };

    test('a service whose value is not a list of 1-2 strings is skipped', () {
      final geometry = parseBusrouterRoutes({
        ...good(200),
        'NOTLIST': 'abc',
        'EMPTY': <String>[],
        'THREE': ['a', 'b', 'c'],
        'MIXED': ['a', 3],
        'NULLS': [null],
      });
      expect(geometry.serviceCount, 200);
      for (final bad in ['NOTLIST', 'EMPTY', 'THREE', 'MIXED', 'NULLS']) {
        expect(geometry.encoded(bad, 0), isNull);
      }
      expect(geometry.encoded('S0', 0), 'abc0');
    });

    test('an encoded line of more than 20,000 characters is invalid (#59)', () {
      final atCap = 'a' * 20000;
      expect(
        parseBusrouterRoutes({
          'S': [atCap],
        }).encoded('S', 0),
        atCap,
      );
      expect(
        () => parseBusrouterRoutes({
          'S': ['a' * 20001],
        }),
        unavailable(),
      );
    });

    test('exactly the allowed invalid share passes, one more fails', () {
      // 1 of 20 is 5 %, which is not more than maxInvalidShare.
      expect(parseBusrouterRoutes({...good(19), 'BAD': 1}).serviceCount, 19);
      expect(
        () => parseBusrouterRoutes({...good(19), 'BAD': 1, 'BAD2': 2}),
        unavailable(),
      );
    });

    test('more than maxInvalidShare invalid → StaticDataUnavailable', () {
      expect(
        () => parseBusrouterRoutes({
          ...good(10),
          for (var i = 0; i < 10; i++) 'BAD$i': 'x',
        }),
        unavailable(),
      );
    });

    test('not an object, or an empty object → StaticDataUnavailable', () {
      expect(() => parseBusrouterRoutes([1, 2]), unavailable());
      expect(() => parseBusrouterRoutes(null), unavailable());
      expect(() => parseBusrouterRoutes('x'), unavailable());
      expect(() => parseBusrouterRoutes(<String, Object?>{}), unavailable());
    });

    test('every entry invalid → StaticDataUnavailable', () {
      expect(() => parseBusrouterRoutes({'A': 1}), unavailable());
    });
  });

  group('BusrouterRouteGeometryRepository', () {
    late int calls;
    late List<Uri> urls;

    BusrouterRouteGeometryRepository repo(
      FutureOr<http.Response> Function() respond,
    ) => BusrouterRouteGeometryRepository(
      JsonHttpClient(
        MockClient((r) async {
          calls++;
          urls.add(r.url);
          return respond();
        }),
        timeout: const Duration(milliseconds: 200),
        delay: (_) async {},
      ),
    );

    http.Response ok() => http.Response.bytes(utf8.encode(routesBody), 200);

    setUp(() {
      calls = 0;
      urls = [];
    });

    test('nothing is fetched until load(); then one GET to routes', () async {
      final r = repo(ok);
      expect(calls, 0);
      final geometry = await r.load();
      expect(geometry.serviceCount, 6);
      expect(calls, 1);
      expect(urls.single, BusrouterEndpoints.routes);
    });

    // The provider is the only session cache (#60).
    test('routeGeometryProvider holds one download for the session, shared '
        'by concurrent and later reads', () async {
      final c = ProviderContainer(
        retry: noAutomaticRetry,
        overrides: [
          routeGeometryRepositoryProvider.overrideWithValue(repo(ok)),
        ],
      );
      addTearDown(c.dispose);
      final first = await Future.wait([
        c.read(routeGeometryProvider.future),
        c.read(routeGeometryProvider.future),
      ]);
      final later = await c.read(routeGeometryProvider.future);
      expect(identical(first[0], first[1]), isTrue);
      expect(identical(first[0], later), isTrue);
      expect(calls, 1);
    });

    Future<void> failsThenRetries(
      http.Response Function() failure, {
      required int callsPerFailure,
    }) async {
      var fail = true;
      final r = repo(() => fail ? failure() : ok());
      await expectLater(r.load(), unavailable());
      expect(calls, callsPerFailure);
      fail = false;
      expect((await r.load()).serviceCount, 6);
      expect(calls, callsPerFailure + 1);
    }

    test('500 after the client retries → unavailable, not cached', () async {
      await failsThenRetries(
        () => http.Response('down', 500),
        callsPerFailure: 1 + AppTimings.httpMaxRetries,
      );
    });

    test('404 → unavailable, not cached', () async {
      await failsThenRetries(
        () => http.Response('gone', 404),
        callsPerFailure: 1,
      );
    });

    test('429 → unavailable, not cached', () async {
      await failsThenRetries(
        () => http.Response('slow down', 429),
        callsPerFailure: 1,
      );
    });

    test('a body over 4 MiB → unavailable, not cached', () async {
      await failsThenRetries(
        () => http.Response.bytes(
          List.filled(AppTimings.httpMaxResponseBytes + 1, 0x20),
          200,
        ),
        callsPerFailure: 1,
      );
    });

    test('malformed JSON or schema → unavailable', () async {
      await expectLater(
        repo(() => http.Response('<html>', 200)).load(),
        unavailable(),
      );
      await expectLater(
        repo(() => http.Response('[1,2,3]', 200)).load(),
        unavailable(),
      );
    });

    test('network failure → unavailable', () async {
      await expectLater(
        repo(() => throw http.ClientException('offline')).load(),
        unavailable(),
      );
    });
  });
}
