import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sg_smart_commute/core/config/app_config.dart';
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

  group('response size cap', () {
    // A 16-byte cap; `{"code":12345}` is 14 bytes.
    JsonHttpClient capped(http.Client client, {Duration? timeout}) =>
        JsonHttpClient(
          client,
          maxResponseBytes: 16,
          timeout: timeout ?? const Duration(seconds: 10),
          delay: (d) async => delays.add(d),
        );

    /// A 200 response whose body is [body] (a fresh stream per send, since
    /// retries send again), with no Content-Length unless given.
    http.Client streaming(
      Stream<List<int>> Function() body, {
      int? contentLength,
      void Function()? onSend,
    }) => MockClient.streaming((request, _) async {
      onSend?.call();
      return http.StreamedResponse(body(), 200, contentLength: contentLength);
    });

    test('a body within the cap is decoded', () async {
      final c = capped(
        MockClient((_) async => http.Response('{"code":12345}', 200)),
      );
      expect(await c.getJson(uri), {'code': 12345});
    });

    test('a body over the cap → InvalidApiResponse, never retried', () async {
      var calls = 0;
      final c = capped(
        streaming(
          () => Stream.fromIterable([
            utf8.encode('{"code":'),
            utf8.encode('123456789}'),
          ]),
          onSend: () => calls++,
        ),
      );
      await expectLater(c.getJson(uri), throwsA(isA<InvalidApiResponse>()));
      expect(calls, 1);
    });

    test(
      'a Content-Length over the cap is rejected; the body is cancelled unread',
      () async {
        var cancelled = false;
        var dataRequested = false;
        final body = StreamController<List<int>>(
          onCancel: () => cancelled = true,
          onResume: () => dataRequested = true,
        );
        final c = capped(streaming(() => body.stream, contentLength: 1 << 20));
        await expectLater(c.getJson(uri), throwsA(isA<InvalidApiResponse>()));
        await pumpEventQueue();
        expect(cancelled, isTrue);
        expect(dataRequested, isFalse);
        await body.close();
      },
    );

    test('reading stops as soon as the cap is passed', () async {
      var chunksSent = 0;
      Stream<List<int>> endless() async* {
        while (true) {
          chunksSent++;
          yield List<int>.filled(8, 0x20); // spaces
        }
      }

      final c = capped(streaming(endless));
      await expectLater(c.getJson(uri), throwsA(isA<InvalidApiResponse>()));
      expect(chunksSent, lessThan(5));
    });

    test('a body that stalls → timeout → NetworkUnavailable', () async {
      final bodies = <StreamController<List<int>>>[];
      Stream<List<int>> stalled() {
        final body = StreamController<List<int>>()..add(utf8.encode('{"co'));
        bodies.add(body);
        return body.stream;
      }

      final c = capped(
        streaming(stalled),
        timeout: const Duration(milliseconds: 50),
      );
      await expectLater(c.getJson(uri), throwsA(isA<NetworkUnavailable>()));
      expect(bodies, hasLength(3)); // first try + 2 retries
      for (final b in bodies) {
        await b.close();
      }
    });
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

  group('Retry-After holds the host (#30)', () {
    late DateTime now;
    late Map<String, int> calls;

    JsonHttpClient held(Map<String, String> headers) => JsonHttpClient(
      MockClient((request) async {
        calls[request.url.host] = (calls[request.url.host] ?? 0) + 1;
        return calls[request.url.host] == 1
            ? http.Response('slow down', 429, headers: headers)
            : http.Response('{"ok":1}', 200);
      }),
      delay: (d) async => delays.add(d),
      clock: () => now,
    );

    setUp(() {
      now = DateTime.utc(2026, 10, 3, 4);
      calls = {};
    });

    test(
      'until it has passed, nothing is sent: the time left is reported',
      () async {
        final c = held({'retry-after': '7'});
        await expectLater(c.getJson(uri), throwsA(isA<ApiRateLimited>()));

        now = now.add(const Duration(seconds: 3));
        await expectLater(
          c.getJson(uri),
          throwsA(
            isA<ApiRateLimited>()
                .having(
                  (e) => e.retryAfter,
                  'retryAfter',
                  const Duration(seconds: 4),
                )
                .having(
                  (e) => e.message,
                  'message',
                  contains('retry in 4 seconds'),
                ),
          ),
        );
        expect(calls[uri.host], 1, reason: 'the held request never went out');

        now = now.add(const Duration(seconds: 4));
        expect(await c.getJson(uri), {'ok': 1});
        expect(calls[uri.host], 2);
      },
    );

    test('only that host is held', () async {
      final c = held({'retry-after': '7'});
      await expectLater(c.getJson(uri), throwsA(isA<ApiRateLimited>()));
      final other = Uri.parse('https://other.example.test/x');
      await expectLater(c.getJson(other), throwsA(isA<ApiRateLimited>()));
      expect(calls, {uri.host: 1, other.host: 1});
    });

    test('without Retry-After nothing is held', () async {
      final c = held({});
      await expectLater(
        c.getJson(uri),
        throwsA(
          isA<ApiRateLimited>()
              .having((e) => e.retryAfter, 'retryAfter', isNull)
              .having((e) => e.message, 'message', contains('in a moment')),
        ),
      );
      expect(await c.getJson(uri), {'ok': 1});
    });

    test('a long Retry-After is capped', () async {
      final c = held({'retry-after': '86400'});
      await expectLater(
        c.getJson(uri),
        throwsA(
          isA<ApiRateLimited>().having(
            (e) => e.retryAfter,
            'retryAfter',
            AppTimings.maxRetryAfter,
          ),
        ),
      );
      now = now.add(AppTimings.maxRetryAfter);
      expect(await c.getJson(uri), {'ok': 1});
    });

    test(
      'a held host does not hold another host, which keeps working',
      () async {
        final sent = <Uri>[];
        final c = JsonHttpClient(
          MockClient((request) async {
            sent.add(request.url);
            return request.url.host == uri.host
                ? http.Response(
                    'slow down',
                    429,
                    headers: {'retry-after': '30'},
                  )
                : http.Response('{"ok":2}', 200);
          }),
          delay: (d) async => delays.add(d),
          clock: () => now,
        );
        final other = Uri.parse('https://other.example.test/x');

        await expectLater(c.getJson(uri), throwsA(isA<ApiRateLimited>()));
        // Another path on the held host is held too (the limit is per host).
        await expectLater(
          c.getJson(uri.replace(path: '/y')),
          throwsA(isA<ApiRateLimited>()),
        );
        expect(await c.getJson(other), {'ok': 2});
        expect(await c.getJson(other), {'ok': 2});
        expect(sent, [uri, other, other]);
      },
    );

    test('a held request fails before taking a rate-limiter grant', () async {
      var grants = 0;
      final c = JsonHttpClient(
        MockClient(
          (_) async =>
              http.Response('slow down', 429, headers: {'retry-after': '9'}),
        ),
        delay: (d) async => delays.add(d),
        clock: () => now,
        rateLimiterFor: (_) => _CountingLimiter(() => grants++),
      );
      await expectLater(c.getJson(uri), throwsA(isA<ApiRateLimited>()));
      expect(grants, 1);
      now = now.add(const Duration(seconds: 2));
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
      expect(grants, 1, reason: 'the held request used no grant');
    });

    test('identical concurrent requests share one send and one 429', () async {
      final gate = Completer<void>();
      var sends = 0;
      final c = JsonHttpClient(
        MockClient((_) async {
          sends++;
          await gate.future;
          return http.Response('slow down', 429, headers: {'retry-after': '5'});
        }),
        delay: (d) async => delays.add(d),
        clock: () => now,
      );
      final a = c.getJson(uri);
      final b = c.getJson(uri);
      gate.complete();
      await expectLater(a, throwsA(isA<ApiRateLimited>()));
      await expectLater(b, throwsA(isA<ApiRateLimited>()));
      expect(sends, 1);
      await expectLater(c.getJson(uri), throwsA(isA<ApiRateLimited>()));
      expect(sends, 1, reason: 'held after the shared 429');
    });

    test(
      'a request already sent when the hold starts keeps its answer',
      () async {
        final slow = Completer<void>();
        final c = JsonHttpClient(
          MockClient((request) async {
            if (request.url.path == '/slow') {
              await slow.future;
              return http.Response('{"ok":"slow"}', 200);
            }
            return http.Response(
              'slow down',
              429,
              headers: {'retry-after': '5'},
            );
          }),
          delay: (d) async => delays.add(d),
          clock: () => now,
        );
        final inFlight = c.getJson(uri.replace(path: '/slow'));
        await expectLater(c.getJson(uri), throwsA(isA<ApiRateLimited>()));
        slow.complete();
        expect(await inFlight, {'ok': 'slow'});
      },
    );

    test('of two concurrent 429s, the longer Retry-After wins', () async {
      final first = Completer<void>();
      final c = JsonHttpClient(
        MockClient((request) async {
          if (request.url.path == '/long') {
            return http.Response('', 429, headers: {'retry-after': '30'});
          }
          await first.future;
          return http.Response('', 429, headers: {'retry-after': '5'});
        }),
        delay: (d) async => delays.add(d),
        clock: () => now,
      );
      final short = c.getJson(uri.replace(path: '/short'));
      await expectLater(
        c.getJson(uri.replace(path: '/long')),
        throwsA(isA<ApiRateLimited>()),
      );
      first.complete();
      await expectLater(short, throwsA(isA<ApiRateLimited>()));

      now = now.add(const Duration(seconds: 10));
      await expectLater(
        c.getJson(uri),
        throwsA(
          isA<ApiRateLimited>().having(
            (e) => e.retryAfter,
            'retryAfter',
            const Duration(seconds: 20),
          ),
        ),
      );
    });

    for (final (header, why) in [
      ('', 'empty'),
      ('abc', 'not a number'),
      ('-5', 'negative'),
      ('+7', 'signed'),
      ('1.5', 'fractional'),
      ('0', 'zero'),
      ('Wed, 21 Oct 2026 07:28:00 GMT', 'HTTP-date'),
    ]) {
      test('a $why Retry-After ("$header") sets no hold', () async {
        final c = held({'retry-after': header});
        await expectLater(
          c.getJson(uri),
          throwsA(
            isA<ApiRateLimited>()
                .having((e) => e.retryAfter, 'retryAfter', isNull)
                .having((e) => e.message, 'message', contains('in a moment')),
          ),
        );
        expect(await c.getJson(uri), {'ok': 1});
        expect(calls[uri.host], 2);
      });
    }

    test('surrounding whitespace is tolerated', () async {
      final c = held({'retry-after': ' 7 '});
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
    });

    for (final header in [
      '9223372036854775807', // int max: seconds → microseconds would overflow
      '99999999999999999999999', // beyond int: tryParse gives null
    ]) {
      test('a huge Retry-After ($header) is capped, never wrapped', () async {
        final c = held({'retry-after': header});
        await expectLater(
          c.getJson(uri),
          throwsA(
            isA<ApiRateLimited>().having(
              (e) => e.retryAfter,
              'retryAfter',
              AppTimings.maxRetryAfter,
            ),
          ),
        );
        now = now.add(AppTimings.maxRetryAfter - const Duration(seconds: 1));
        await expectLater(c.getJson(uri), throwsA(isA<ApiRateLimited>()));
        now = now.add(const Duration(seconds: 1));
        expect(await c.getJson(uri), {'ok': 1});
        expect(calls[uri.host], 2);
      });
    }

    test('5xx retries are unchanged and set no hold', () async {
      var sends = 0;
      final c = JsonHttpClient(
        MockClient((_) async {
          sends++;
          return sends < 3
              ? http.Response('', 503, headers: {'retry-after': '30'})
              : http.Response('{"ok":3}', 200);
        }),
        delay: (d) async => delays.add(d),
        clock: () => now,
      );
      expect(await c.getJson(uri), {'ok': 3});
      expect(sends, 3);
      expect(delays, [
        const Duration(milliseconds: 500),
        const Duration(seconds: 1),
      ]);
      expect(await c.getJson(uri), {'ok': 3}, reason: 'no hold after a 503');
    });
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

    test(
      'a request queued for a grant when a 429 sets the hold is not sent',
      () {
        fakeAsync((async) {
          final limiter = RollingWindowRateLimiter(
            maxRequests: 1,
            window: const Duration(seconds: 10),
          );
          final sends = <Uri>[];
          final c = JsonHttpClient(
            MockClient((request) async {
              sends.add(request.url);
              return sends.length == 1
                  ? http.Response('', 429, headers: {'retry-after': '30'})
                  : http.Response('{"ok":1}', 200);
            }),
            delay: (_) async {},
            rateLimiterFor: (_) => limiter,
            clock: () => clock.now(), // the limiter's fake time
          );
          Object? first;
          Object? queued;
          c.getJson(limitedN(1)).catchError((Object e) => first = e);
          c.getJson(limitedN(2)).catchError((Object e) => queued = e);
          async.flushMicrotasks();
          expect(first, isA<ApiRateLimited>());
          expect(queued, isNull, reason: 'still waiting for its grant');

          async.elapse(const Duration(seconds: 10)); // the grant arrives
          expect(
            queued,
            isA<ApiRateLimited>().having(
              (e) => e.retryAfter,
              'retryAfter',
              const Duration(seconds: 20),
            ),
          );
          expect(sends, [
            limitedN(1),
          ], reason: 'the queued request never went out');

          async.elapse(const Duration(seconds: 20)); // hold over
          Object? later;
          c.getJson(limitedN(3)).then((v) => later = v);
          async.flushMicrotasks();
          expect(later, {'ok': 1});
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

  group('app wiring (jsonHttpClientProvider)', () {
    test('OneMap searches are paced; data.gov.sg and others are not '
        'held up by it', () {
      fakeAsync((async) {
        final sends = <(Duration, String)>[];
        final container = ProviderContainer(
          overrides: [
            httpClientProvider.overrideWithValue(
              MockClient((request) async {
                sends.add((async.elapsed, request.url.host));
                return http.Response('{"found":0,"results":[]}', 200);
              }),
            ),
          ],
        );
        addTearDown(container.dispose);
        final client = container.read(jsonHttpClientProvider);

        client.getJson(OneMapEndpoints.search('aaa'));
        client.getJson(OneMapEndpoints.search('bbb'));
        client.getJson(OneMapEndpoints.search('ccc'));
        client.getJson(NeaEndpoints.psi);
        client.getJson(uri);
        async.flushMicrotasks();
        expect(
          sends.map((s) => s.$2),
          unorderedEquals([
            OneMapEndpoints.host,
            NeaEndpoints.psi.host,
            uri.host,
          ]),
        );

        async.elapse(const Duration(seconds: 2));
        final oneMapTimes = [
          for (final (t, host) in sends)
            if (host == OneMapEndpoints.host) t,
        ];
        expect(oneMapTimes, [
          Duration.zero,
          OneMapRateLimit.window,
          OneMapRateLimit.window * 2,
        ]);
      });
    });
  });
}

/// A limiter that grants at once and counts its grants.
class _CountingLimiter implements RequestRateLimiter {
  _CountingLimiter(this._onGrant);
  final void Function() _onGrant;

  @override
  Future<void> acquire() async => _onGrant();
}
