// The data.gov.sg anonymous limit (6 real-time calls per 10 s) through the
// real UI paths: launch, "Refresh all", a tile's Retry and the area picker's
// Retry. Only the HTTP transport is fake: a server that enforces the limit
// and answers 429 above it. The real repository, JsonHttpClient and limiter
// run unchanged. Time is the test binding's fake clock.
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sg_smart_commute/core/geo/geo.dart';
import 'package:sg_smart_commute/core/http/json_http_client.dart';
import 'package:sg_smart_commute/core/location/location_service.dart';
import 'package:sg_smart_commute/core/time/clock.dart';
import 'package:sg_smart_commute/features/origin/presentation/origin_card.dart';
import 'package:sg_smart_commute/main.dart';

import '../../fakes/fake_location_service.dart';

const bishan = LatLng(1.3508, 103.8485);

/// Shortly after the fixtures' own timestamps, so readings are not stale.
final fixtureNow = DateTime.utc(2026, 10, 1, 12, 20);

/// A data.gov.sg stand-in that enforces the anonymous real-time limit the way
/// the real API does: more than 6 arrivals in any 10 s → 429.
class FakeDataGovSg {
  FakeDataGovSg() : _start = clock.now();

  final DateTime _start;
  final List<({Duration at, String dataset, int status})> requests = [];

  /// Datasets whose next request fails with HTTP 400 (no retry, error tile).
  final Set<String> failNext = {};

  int get rateLimited => requests.where((r) => r.status == 429).length;

  Future<http.Response> handle(http.Request request) async {
    final at = clock.now().difference(_start);
    final dataset = request.url.pathSegments.last;
    final inWindow =
        requests.where((r) => at - r.at < const Duration(seconds: 10)).length +
        1;
    final int status;
    if (inWindow > 6) {
      status = 429;
    } else if (failNext.remove(dataset)) {
      status = 400;
    } else {
      status = 200;
    }
    requests.add((at: at, dataset: dataset, status: status));
    if (status != 200) return http.Response('{}', status);
    return http.Response.bytes(
      File('test/fixtures/$dataset.json').readAsBytesSync(),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}

Widget app(FakeDataGovSg server, LocationService location) => ProviderScope(
  retry: noAutomaticRetry,
  overrides: [
    locationServiceProvider.overrideWithValue(location),
    httpClientProvider.overrideWithValue(MockClient(server.handle)),
    clockProvider.overrideWithValue(() => fixtureNow),
  ],
  child: const SmartCommuteApp(),
);

Finder retryIn(Finder parent) =>
    find.descendant(of: parent, matching: find.text('Retry'));

Finder tile(String key) => find.byKey(Key(key));

Future<void> tapRetry(WidgetTester tester, Finder parent) async {
  final retry = retryIn(parent);
  await tester.ensureVisible(retry);
  await tester.pump();
  await tester.tap(retry);
  await tester.pump();
  await tester.pump();
}

/// A screen tall enough that every card is built at once: the dashboard is a
/// lazy list, so scrolling to a tile could otherwise unbuild the origin card.
void tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Advances fake time and lets queued requests and responses run.
Future<void> advance(WidgetTester tester, Duration by) async {
  await tester.pump(by);
  await tester.pump();
  await tester.pump();
}

const allDatasets = {'two-hr-forecast', 'uv', 'pm25', 'psi'};

void main() {
  testWidgets('launch 4 + Refresh all at 3 s: only 2 more go out, the other 2 '
      'wait for capacity; data.gov.sg never answers 429', (tester) async {
    tallScreen(tester);
    final server = FakeDataGovSg();
    await tester.pumpWidget(
      app(
        server,
        FakeLocationService(access: LocationAccess.granted, position: bishan),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(server.requests, hasLength(4));
    expect(server.requests.every((r) => r.at == Duration.zero), isTrue);

    await advance(tester, const Duration(seconds: 3));
    await tester.tap(find.byKey(const Key('refresh-conditions')));
    await tester.pump();
    await tester.pump();
    expect(server.requests, hasLength(6), reason: 'only 2 of 4 may go out');
    expect(server.rateLimited, 0);

    // Once the launch calls leave the rolling window, the queued two proceed.
    await advance(tester, const Duration(seconds: 8)); // t = 11 s
    expect(server.requests, hasLength(8));
    expect(server.rateLimited, 0);
    expect(server.requests.skip(6).every((r) => r.status == 200), isTrue);
    await tester.pumpAndSettle();
    expect(retryIn(find.byType(Scaffold)), findsNothing);
  });

  testWidgets('a tile Retry waits for capacity instead of drawing a 429', (
    tester,
  ) async {
    tallScreen(tester);
    final server = FakeDataGovSg()..failNext.addAll(allDatasets);
    await tester.pumpWidget(
      app(
        server,
        FakeLocationService(access: LocationAccess.granted, position: bishan),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(server.requests, hasLength(4)); // all four failed: four Retry tiles

    await advance(tester, const Duration(seconds: 1));
    await tapRetry(tester, tile('tile-forecast'));
    await tapRetry(tester, tile('tile-uv'));
    expect(server.requests, hasLength(6));

    await advance(tester, const Duration(seconds: 1)); // t = 2 s
    await tapRetry(tester, tile('tile-psi'));
    expect(server.requests, hasLength(6), reason: 'the 7th call must wait');

    await advance(tester, const Duration(seconds: 9)); // t = 11 s
    expect(server.requests, hasLength(7));
    expect(server.requests.last.dataset, 'psi');
    expect(server.requests.last.status, 200);
    expect(server.rateLimited, 0);
    await tester.pump();
    expect(retryIn(tile('tile-psi')), findsNothing);
  });

  testWidgets('the area picker Retry (same forecast endpoint) is limited too', (
    tester,
  ) async {
    tallScreen(tester);
    final server = FakeDataGovSg()..failNext.addAll(allDatasets);
    await tester.pumpWidget(
      app(server, FakeLocationService(access: LocationAccess.denied)),
    );
    await tester.pump();
    await tester.pump();
    expect(server.requests, hasLength(4));
    expect(find.textContaining('Area list unavailable'), findsOneWidget);

    await advance(tester, const Duration(seconds: 1));
    await tapRetry(tester, tile('tile-uv'));
    await tapRetry(tester, tile('tile-pm25'));
    expect(server.requests, hasLength(6));

    await advance(tester, const Duration(seconds: 1)); // t = 2 s
    await tapRetry(tester, find.byType(OriginCard));
    expect(server.requests, hasLength(6), reason: 'the 7th call must wait');

    await advance(tester, const Duration(seconds: 9)); // t = 11 s
    expect(server.requests, hasLength(7));
    expect(server.requests.last.dataset, 'two-hr-forecast');
    expect(server.requests.last.status, 200);
    expect(server.rateLimited, 0);
    await tester.pump();
    expect(find.textContaining('Area list unavailable'), findsNothing);
  });
}
