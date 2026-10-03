// The Retry-After hold through the real provider seams: the app's
// providers, repositories (NEA, OneMap), parsers, JsonHttpClient and limiters
// run unchanged; only the HTTP transport and the clock are fake.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sg_smart_commute/core/config/app_config.dart';
import 'package:sg_smart_commute/core/errors/app_failure.dart';
import 'package:sg_smart_commute/core/http/json_http_client.dart';
import 'package:sg_smart_commute/core/time/clock.dart';
import 'package:sg_smart_commute/features/environment/environment_providers.dart';
import 'package:sg_smart_commute/features/places/domain/place.dart';
import 'package:sg_smart_commute/features/places/place_providers.dart';
import 'package:sg_smart_commute/main.dart';

http.Response fixture(String path) => http.Response.bytes(
  File('test/fixtures/$path').readAsBytesSync(),
  200,
  headers: {'content-type': 'application/json'},
);

void main() {
  late DateTime now;
  late List<Uri> sent;
  late ProviderContainer container;

  setUp(() {
    now = DateTime.utc(2026, 10, 1, 12, 20);
    sent = [];
    var pm25Calls = 0;
    container = ProviderContainer(
      retry: noAutomaticRetry,
      overrides: [
        clockProvider.overrideWithValue(() => now),
        httpClientProvider.overrideWithValue(
          MockClient((request) async {
            sent.add(request.url);
            final url = request.url;
            if (url.host == OneMapEndpoints.host) {
              return fixture('onemap/mall-vivocity.json');
            }
            final dataset = url.pathSegments.last;
            if (dataset == 'pm25' && ++pm25Calls == 1) {
              return http.Response('', 429, headers: {'retry-after': '10'});
            }
            return fixture('$dataset.json');
          }),
        ),
      ],
    );
    addTearDown(container.dispose);
  });

  test('a data.gov.sg 429 holds data.gov.sg only, until Retry-After has '
      'passed; then the same provider loads again', () async {
    await expectLater(
      container.read(pm25SnapshotProvider.future),
      throwsA(
        isA<ApiRateLimited>()
            .having(
              (e) => e.retryAfter,
              'retryAfter',
              const Duration(seconds: 10),
            )
            .having((e) => e.message, 'message', contains('10 seconds')),
      ),
    );
    expect(sent, [NeaEndpoints.pm25]);

    // Another dataset on the same host is refused locally, with the time left.
    now = now.add(const Duration(seconds: 4));
    await expectLater(
      container.read(psiSnapshotProvider.future),
      throwsA(
        isA<ApiRateLimited>().having(
          (e) => e.retryAfter,
          'retryAfter',
          const Duration(seconds: 6),
        ),
      ),
    );
    expect(sent, [NeaEndpoints.pm25], reason: 'PSI never reached the network');

    // OneMap is another host: place search still works.
    final places = await container
        .read(placeSearchRepositoryProvider)
        .search('VivoCity', mode: SearchMode.submit);
    expect(places.map((p) => p.displayName), contains('VIVOCITY'));
    expect(sent.last.host, OneMapEndpoints.host);

    // Retry after the hold: the tile's provider loads normally.
    now = now.add(const Duration(seconds: 6));
    container.invalidate(pm25SnapshotProvider);
    final pm25 = await container.read(pm25SnapshotProvider.future);
    expect(pm25.values, isNotEmpty);
    expect(sent.last, NeaEndpoints.pm25);
  });
}
