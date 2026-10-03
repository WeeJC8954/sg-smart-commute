import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/core/errors/app_failure.dart';
import 'package:sg_smart_commute/core/errors/failure_guard.dart';

void main() {
  group('AppFailure', () {
    test('toString carries the technical detail; message never does', () {
      const f = InvalidApiResponse('uv: missing index');
      expect(f.detail, 'uv: missing index');
      expect(f.toString(), contains('uv: missing index'));
      expect(f.message, isNot(contains('index')));
      expect(const NetworkUnavailable().detail, isNull);
      expect(
        const NetworkUnavailable().toString(),
        'NetworkUnavailable: ${const NetworkUnavailable().message}',
      );
    });

    test('the static-data message follows the dataset', () {
      expect(
        const StaticDataUnavailable(StaticDataset.mrtStations).message,
        'MRT station data is unavailable.',
      );
      expect(
        const StaticDataUnavailable(StaticDataset.busRoutes).message,
        'Bus data is unavailable right now.',
      );
      expect(
        const StaticDataUnavailable(StaticDataset.busRouteGeometry).message,
        'The bus route line is unavailable right now.',
      );
    });

    test('a rate limit says how long to wait when it is known', () {
      expect(
        const ApiRateLimited().message,
        'The data service is busy. Please retry in a moment.',
      );
      String wait(Duration d) => ApiRateLimited(retryAfter: d).message;
      expect(wait(const Duration(seconds: 1)), endsWith('retry in 1 second.'));
      expect(
        wait(const Duration(milliseconds: 9200)),
        endsWith('retry in 10 seconds.'),
      );
      expect(wait(const Duration(minutes: 5)), endsWith('retry in 5 minutes.'));
      expect(wait(Duration.zero), endsWith('in a moment.'));
    });
  });

  group('guardAppFailure', () {
    test('passes values and AppFailures through unchanged', () async {
      expect(await guardAppFailure(() async => 7, context: 't'), 7);
      const failure = NetworkUnavailable();
      await expectLater(
        guardAppFailure<int>(() async => throw failure, context: 't'),
        throwsA(same(failure)),
      );
    });

    test('anything else becomes InvalidApiResponse naming the context', () {
      expect(
        guardAppFailure<int>(
          () async => throw const FormatException('bad'),
          context: 'uv',
        ),
        throwsA(
          isA<InvalidApiResponse>().having(
            (e) => e.detail,
            'detail',
            allOf(startsWith('uv: '), contains('bad')),
          ),
        ),
      );
      expect(
        () => guardAppFailureSync<int>(
          () => throw StateError('no element'),
          context: 'psi',
        ),
        throwsA(
          isA<InvalidApiResponse>().having(
            (e) => e.detail,
            'detail',
            startsWith('psi: '),
          ),
        ),
      );
    });
  });
}
