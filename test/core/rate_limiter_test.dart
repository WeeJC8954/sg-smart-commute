import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/core/config/app_config.dart';
import 'package:sg_smart_commute/core/http/rate_limiter.dart';

void main() {
  /// Calls `acquire` [n] times and records the fake time of each grant.
  void acquireAll(
    FakeAsync async,
    RequestRateLimiter limiter,
    int n,
    List<Duration> grants,
  ) {
    for (var i = 0; i < n; i++) {
      limiter.acquire().then((_) => grants.add(async.elapsed));
    }
  }

  RollingWindowRateLimiter sixPerTen() => RollingWindowRateLimiter(
    maxRequests: 6,
    window: const Duration(seconds: 10),
  );

  test('a burst up to the limit is granted at once, not serialised', () {
    fakeAsync((async) {
      final grants = <Duration>[];
      acquireAll(async, sixPerTen(), 6, grants);
      async.flushMicrotasks();
      expect(grants, List.filled(6, Duration.zero));
    });
  });

  test('4 at 0 s + 4 at 3 s: two more go at 3 s, the rest when the window '
      'expires (10 s), in FIFO order', () {
    fakeAsync((async) {
      final limiter = sixPerTen();
      final grants = <Duration>[];
      acquireAll(async, limiter, 4, grants);
      async.elapse(const Duration(seconds: 3));
      acquireAll(async, limiter, 4, grants);
      async.flushMicrotasks();
      expect(grants, hasLength(6));

      async.elapse(const Duration(milliseconds: 6999)); // t = 9.999 s
      expect(grants, hasLength(6));
      async.elapse(const Duration(milliseconds: 1)); // t = 10 s
      expect(grants, [
        ...List.filled(4, Duration.zero),
        const Duration(seconds: 3),
        const Duration(seconds: 3),
        const Duration(seconds: 10),
        const Duration(seconds: 10),
      ]);
    });
  });

  test('the window rolls: capacity frees as each grant ages out, not in '
      'fixed buckets', () {
    fakeAsync((async) {
      final limiter = sixPerTen();
      final grants = <Duration>[];
      acquireAll(async, limiter, 3, grants); // t = 0
      async.elapse(const Duration(seconds: 5));
      acquireAll(async, limiter, 3, grants); // t = 5
      async.elapse(const Duration(seconds: 1));
      acquireAll(async, limiter, 4, grants); // t = 6: all four must wait
      async.elapse(const Duration(seconds: 20));
      expect(grants.skip(6), const [
        Duration(seconds: 10), // the three from t = 0 age out
        Duration(seconds: 10),
        Duration(seconds: 10),
        Duration(seconds: 15), // then one from t = 5
      ]);
    });
  });

  test('no 10 s window ever holds more than 6 grants (dense load)', () {
    fakeAsync((async) {
      final limiter = sixPerTen();
      final grants = <Duration>[];
      for (var t = 0; t < 40; t++) {
        acquireAll(async, limiter, 2, grants);
        async.elapse(const Duration(milliseconds: 700));
      }
      async.elapse(const Duration(minutes: 2));
      expect(grants, hasLength(80));
      for (final start in grants) {
        final inWindow = grants
            .where((g) => g >= start && g - start < const Duration(seconds: 10))
            .length;
        expect(inWindow, lessThanOrEqualTo(6), reason: 'window from $start');
      }
    });
  });

  test('the data.gov.sg config: 6 per 10 s plus a 1 s latency margin', () {
    expect(DataGovSgRateLimit.maxRequests, 6);
    expect(DataGovSgRateLimit.window, const Duration(seconds: 10));
    expect(DataGovSgRateLimit.safetyMargin, const Duration(seconds: 1));
  });

  test('only data.gov.sg real-time URLs are covered', () {
    for (final uri in [
      NeaEndpoints.twoHourForecast,
      NeaEndpoints.uv,
      NeaEndpoints.pm25,
      NeaEndpoints.psi,
    ]) {
      expect(DataGovSgRateLimit.appliesTo(uri), isTrue, reason: '$uri');
    }
    for (final uri in [
      Uri.parse('https://www.onemap.gov.sg/api/common/elastic/search'),
      Uri.parse('https://photon.komoot.io/api/'),
      Uri.parse('https://arrivelah2.busrouter.sg/?id=83139'),
      Uri.parse('https://api-open.data.gov.sg/v1/public/api/datasets'),
    ]) {
      expect(DataGovSgRateLimit.appliesTo(uri), isFalse, reason: '$uri');
    }
  });
}
