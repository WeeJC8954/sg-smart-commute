// ArriveLah repository (mock HTTP) and the arrival cache (guide v2.1 §15,
// §18): success, network error, timeout, malformed, HTTP failure, TTL,
// concurrent dedup, failures not cached.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sg_smart_commute/core/errors/app_failure.dart';
import 'package:sg_smart_commute/core/http/json_http_client.dart';
import 'package:sg_smart_commute/features/bus_arrival/data/arrivelah_bus_arrival_repository.dart';
import 'package:sg_smart_commute/features/bus_arrival/domain/bus_arrival.dart';
import 'package:sg_smart_commute/features/bus_arrival/domain/bus_arrival_cache.dart';

import '../../../integration_test/fakes/fake_bus_arrival_repository.dart';

final stop03019 = File('test/fixtures/arrivelah/stop_03019.json')
    .readAsStringSync();

ArriveLahBusArrivalRepository repo(
  Future<http.Response> Function(http.Request) handler, {
  Duration timeout = const Duration(seconds: 10),
}) => ArriveLahBusArrivalRepository(
  JsonHttpClient(
    MockClient(handler),
    timeout: timeout,
    delay: (_) async {}, // no real backoff waits
  ),
);

Matcher throwsFailure<T extends AppFailure>() => throwsA(isA<T>());

void main() {
  group('ArriveLahBusArrivalRepository', () {
    test(
      'one GET per stop to ?id=<code>, parsed into domain arrivals',
      () async {
        final requested = <Uri>[];
        final r = repo((req) async {
          requested.add(req.url);
          return http.Response(stop03019, 200);
        });
        final stop = await r.arrivalsAt('03019');
        expect(
          requested.single.toString(),
          'https://arrivelah2.busrouter.sg/?id=03019',
        );
        expect(stop.services, hasLength(10));
        // Captured at about 11:00 SGT.
        final capturedAt = DateTime.utc(2026, 10, 2, 3);
        expect(nextArrivals(stop, '57', now: capturedAt), hasLength(3));
      },
    );

    test(
      'network error → NetworkUnavailable (after bounded retries)',
      () async {
        var calls = 0;
        final r = repo((_) async {
          calls++;
          throw http.ClientException('offline');
        });
        await expectLater(
          r.arrivalsAt('03019'),
          throwsFailure<NetworkUnavailable>(),
        );
        expect(calls, 3); // 1 + 2 retries
      },
    );

    test('timeout → NetworkUnavailable', () async {
      final r = repo(
        (_) => Completer<http.Response>().future, // never answers
        timeout: const Duration(milliseconds: 20),
      );
      await expectLater(
        r.arrivalsAt('03019'),
        throwsFailure<NetworkUnavailable>(),
      );
    });

    test('body is not JSON → InvalidApiResponse', () async {
      final r = repo((_) async => http.Response('<html>oops</html>', 200));
      await expectLater(
        r.arrivalsAt('03019'),
        throwsFailure<InvalidApiResponse>(),
      );
    });

    test('HTTP 200 with {"error": …} → BusArrivalUnavailable', () async {
      final r = repo(
        (_) async => http.Response(
          '{"error":"Failed to retrieve bus data.","statusCode":500}',
          200,
        ),
      );
      await expectLater(
        r.arrivalsAt('03019'),
        throwsFailure<BusArrivalUnavailable>(),
      );
    });

    test('HTTP 5xx → ApiUnavailable; 4xx is not retried', () async {
      var calls = 0;
      final r5 = repo((_) async {
        calls++;
        return http.Response('', 503);
      });
      await expectLater(r5.arrivalsAt('1'), throwsFailure<ApiUnavailable>());
      expect(calls, 3);

      calls = 0;
      final r4 = repo((_) async {
        calls++;
        return http.Response('', 404);
      });
      await expectLater(r4.arrivalsAt('1'), throwsFailure<ApiUnavailable>());
      expect(calls, 1);
    });

    test(
      'empty service list (unknown stop) is a valid, empty answer',
      () async {
        final r = repo((_) async => http.Response('{"services":[]}', 200));
        expect((await r.arrivalsAt('99999')).services, isEmpty);
      },
    );
  });

  group('BusArrivalCache', () {
    late FakeBusArrivalRepository fake;
    late DateTime now;
    late BusArrivalCache cache;

    setUp(() {
      fake = FakeBusArrivalRepository();
      now = DateTime.utc(2026, 10, 2, 3);
      cache = BusArrivalCache(
        fake,
        () => now,
        ttl: const Duration(seconds: 15),
      );
    });

    test('a hit within the TTL makes no request', () async {
      await cache.arrivalsAt('BSH1');
      now = now.add(const Duration(seconds: 14));
      await cache.arrivalsAt('BSH1');
      expect(fake.calls['BSH1'], 1);
    });

    test('at or after the TTL → fetched again', () async {
      await cache.arrivalsAt('BSH1');
      now = now.add(const Duration(seconds: 15));
      await cache.arrivalsAt('BSH1');
      expect(fake.calls['BSH1'], 2);
    });

    test('the TTL counts from when the answer arrived', () async {
      fake.hold('BSH1');
      final first = cache.arrivalsAt('BSH1');
      now = now.add(const Duration(seconds: 10)); // slow answer
      fake.release('BSH1');
      await first;
      now = now.add(const Duration(seconds: 10)); // 20 s after the request
      await cache.arrivalsAt('BSH1');
      expect(fake.calls['BSH1'], 1);
    });

    test('concurrent requests for one stop share one call; '
        'other stops are separate', () async {
      fake.hold('BSH1');
      final a = cache.arrivalsAt('BSH1');
      final b = cache.arrivalsAt('BSH1');
      final c = cache.arrivalsAt('BSH2');
      fake.release('BSH1');
      final results = await Future.wait([a, b, c]);
      expect(identical(results[0], results[1]), isTrue);
      expect(fake.calls, {'BSH1': 1, 'BSH2': 1});
    });

    test(
      'a failure is not cached: the next request (Retry) tries again',
      () async {
        fake.failure = const NetworkUnavailable();
        await expectLater(
          cache.arrivalsAt('BSH1'),
          throwsFailure<NetworkUnavailable>(),
        );
        fake.failure = null;
        final stop = await cache.arrivalsAt('BSH1');
        expect(stop.services, isNotEmpty);
        expect(fake.calls['BSH1'], 2);
      },
    );

    test(
      'a non-typed error from the repository leaves as InvalidApiResponse',
      () async {
        final cache2 = BusArrivalCache(
          _ThrowingRepository(),
          () => now,
          ttl: const Duration(seconds: 15),
        );
        await expectLater(
          cache2.arrivalsAt('1'),
          throwsFailure<InvalidApiResponse>(),
        );
      },
    );
  });
}

class _ThrowingRepository extends FakeBusArrivalRepository {
  @override
  Future<StopArrivals> arrivalsAt(String busStopCode) async =>
      throw StateError('boom');
}
