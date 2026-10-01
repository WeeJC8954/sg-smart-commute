import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sg_smart_commute/core/errors/app_failure.dart';
import 'package:sg_smart_commute/core/http/json_http_client.dart';
import 'package:sg_smart_commute/core/http/rate_limiter.dart';

final uri = Uri.parse('https://api.example.test/x');

void main() {
  late List<Duration> delays;

  JsonHttpClient make(MockClientHandler handler, {Duration? timeout}) =>
      JsonHttpClient(
        MockClient(handler),
        timeout: timeout ?? const Duration(seconds: 10),
        delay: (d) async => delays.add(d),
      );

  setUp(() => delays = []);

  test('decodes a 200 JSON body', () async {
    final c = make((_) async => http.Response('{"code":0}', 200));
    expect(await c.getJson(uri), {'code': 0});
  });

  test('decodes UTF-8 (µg/m³, ⇄) correctly', () async {
    // No charset in Content-Type, as with many APIs: bytes must still be UTF-8.
    final c = make(
      (_) async => http.Response.bytes(
        utf8.encode('{"s":"µg ⇄"}'),
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
    expect(await c.getJson(uri), {'s': 'µg ⇄'});
  });

  test('malformed JSON → InvalidApiResponse, no retry', () async {
    var calls = 0;
    final c = make((_) async {
      calls++;
      return http.Response('<html>', 200);
    });
    await expectLater(c.getJson(uri), throwsA(isA<InvalidApiResponse>()));
    expect(calls, 1);
  });

  test('429 → ApiRateLimited with Retry-After, never retried', () async {
    var calls = 0;
    final c = make((_) async {
      calls++;
      return http.Response('slow down', 429, headers: {'retry-after': '7'});
    });
    await expectLater(
      c.getJson(uri),
      throwsA(
        isA<ApiRateLimited>().having(
          (e) => e.retryAfter,
          'retryAfter',
          const Duration(seconds: 7),
        ),
      ),
    );
    expect(calls, 1);
  });

  test('401 / 403 → ApiUnauthorized, never retried', () async {
    for (final code in [401, 403]) {
      var calls = 0;
      final c = make((_) async {
        calls++;
        return http.Response('', code);
      });
      await expectLater(c.getJson(uri), throwsA(isA<ApiUnauthorized>()));
      expect(calls, 1);
    }
  });

  test('other 4xx → ApiUnavailable, never retried', () async {
    var calls = 0;
    final c = make((_) async {
      calls++;
      return http.Response('', 404);
    });
    await expectLater(c.getJson(uri), throwsA(isA<ApiUnavailable>()));
    expect(calls, 1);
  });

  test(
    '5xx is retried at most twice with backoff, then ApiUnavailable',
    () async {
      var calls = 0;
      final c = make((_) async {
        calls++;
        return http.Response('', 503);
      });
      await expectLater(c.getJson(uri), throwsA(isA<ApiUnavailable>()));
      expect(calls, 3);
      expect(delays, [
        const Duration(milliseconds: 500),
        const Duration(seconds: 1),
      ]);
    },
  );

  test('5xx then success recovers', () async {
    var calls = 0;
    final c = make(
      (_) async =>
          ++calls == 1 ? http.Response('', 500) : http.Response('[1]', 200),
    );
    expect(await c.getJson(uri), [1]);
    expect(calls, 2);
  });

  test('network error is retried, then NetworkUnavailable', () async {
    var calls = 0;
    final c = make((_) async {
      calls++;
      throw http.ClientException('Failed to fetch', uri);
    });
    await expectLater(c.getJson(uri), throwsA(isA<NetworkUnavailable>()));
    expect(calls, 3);
  });

  test('request timeout → NetworkUnavailable', () async {
    final c = make(
      (_) => Completer<http.Response>().future,
      timeout: const Duration(milliseconds: 10),
    );
    await expectLater(c.getJson(uri), throwsA(isA<NetworkUnavailable>()));
  });

  test('concurrent identical requests are deduplicated', () async {
    var calls = 0;
    final gate = Completer<void>();
    final c = make((_) async {
      calls++;
      await gate.future;
      return http.Response('{"a":1}', 200);
    });
    final a = c.getJson(uri);
    final b = c.getJson(uri);
    gate.complete();
    expect(await a, {'a': 1});
    expect(await b, {'a': 1});
    expect(calls, 1);

    // A later request after completion goes to the network again.
    await c.getJson(uri);
    expect(calls, 2);
  });

  group('with a client-side rate limiter', () {
    final limited = Uri.parse('https://limited.test/a');
    final other = Uri.parse('https://other.test/b');
    Uri limitedN(int i) => Uri.parse('https://limited.test/n$i');

    /// The real client wired like the app: one limiter for one host only.
    /// Records every send with its fake time.
    ({JsonHttpClient client, List<(Duration, Uri)> sends}) wired(
      FakeAsync async, {
      int status = 200,
      Map<String, String> headers = const {},
    }) {
      final limiter = RollingWindowRateLimiter(
        maxRequests: 6,
        window: const Duration(seconds: 10),
      );
      final sends = <(Duration, Uri)>[];
      final client = JsonHttpClient(
        MockClient((request) async {
          sends.add((async.elapsed, request.url));
          return http.Response('{"ok":1}', status, headers: headers);
        }),
        delay: (_) async {},
        rateLimiterFor: (u) => u.host == 'limited.test' ? limiter : null,
      );
      return (client: client, sends: sends);
    }

    test('queued requests go out once the window expires', () {
      fakeAsync((async) {
        final w = wired(async);
        for (var i = 0; i < 8; i++) {
          w.client.getJson(limitedN(i));
        }
        async.flushMicrotasks();
        expect(w.sends, hasLength(6));
        async.elapse(const Duration(seconds: 10));
        expect(w.sends, hasLength(8));
        expect(w.sends.skip(6).map((s) => s.$1), [
          const Duration(seconds: 10),
          const Duration(seconds: 10),
        ]);
      });
    });

    test(
      'other hosts are not limited, even while the limited host is full',
      () {
        fakeAsync((async) {
          final w = wired(async);
          for (var i = 0; i < 7; i++) {
            w.client.getJson(limitedN(i)); // 6 sent, 1 queued
          }
          for (var i = 0; i < 10; i++) {
            w.client.getJson(other.replace(query: 'i=$i'));
          }
          async.flushMicrotasks();
          final otherSends = w.sends.where((s) => s.$2.host == 'other.test');
          expect(otherSends, hasLength(10));
          expect(otherSends.every((s) => s.$1 == Duration.zero), isTrue);
          expect(
            w.sends.where((s) => s.$2.host == 'limited.test'),
            hasLength(6),
          );
        });
      },
    );

    test('concurrent identical requests share one send, also while queued', () {
      fakeAsync((async) {
        final w = wired(async);
        for (var i = 0; i < 6; i++) {
          w.client.getJson(limitedN(i)); // fill the window
        }
        final results = <Object?>[];
        w.client.getJson(limited).then(results.add);
        w.client.getJson(limited).then(results.add); // same URI, queued
        async.flushMicrotasks();
        expect(w.sends, hasLength(6));

        async.elapse(const Duration(seconds: 10));
        expect(w.sends.where((s) => s.$2 == limited), hasLength(1));
        expect(results, [
          {'ok': 1},
          {'ok': 1},
        ]);

        // After completion, a new call sends again (and takes a slot).
        w.client.getJson(limited);
        async.flushMicrotasks();
        expect(w.sends.where((s) => s.$2 == limited), hasLength(2));
      });
    });

    test(
      'a real 429 is still ApiRateLimited with Retry-After, not retried',
      () {
        fakeAsync((async) {
          final w = wired(async, status: 429, headers: {'retry-after': '7'});
          Object? error;
          w.client.getJson(limited).catchError((Object e) {
            error = e;
            return null;
          });
          async.flushMicrotasks();
          expect(
            error,
            isA<ApiRateLimited>().having(
              (e) => e.retryAfter,
              'retryAfter',
              const Duration(seconds: 7),
            ),
          );
          expect(w.sends, hasLength(1));
        });
      },
    );

    test('each retry of a 5xx waits for its own grant', () {
      fakeAsync((async) {
        final limiter = RollingWindowRateLimiter(
          maxRequests: 2,
          window: const Duration(seconds: 10),
        );
        final sends = <Duration>[];
        final client = JsonHttpClient(
          MockClient((_) async {
            sends.add(async.elapsed);
            return http.Response('down', 503);
          }),
          delay: (_) async {},
          rateLimiterFor: (_) => limiter,
        );
        client.getJson(limited).catchError((Object _) => null);
        async.elapse(const Duration(seconds: 30));
        // 1 try + 2 retries; the third send needs a free slot.
        expect(sends, const [
          Duration.zero,
          Duration.zero,
          Duration(seconds: 10),
        ]);
      });
    });
  });
}
