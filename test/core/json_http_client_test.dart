import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sg_smart_commute/core/errors/app_failure.dart';
import 'package:sg_smart_commute/core/http/json_http_client.dart';

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
}
