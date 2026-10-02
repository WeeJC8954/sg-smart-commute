// PlaceSearchConfig is the single source of the place-search tunables
// (debounce, cache TTL, minimum query length). These tests check two things:
// every consumer defaults to it, and changing the injected value changes the
// behaviour, so no second hard-coded copy can hide behind a passing test.
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sg_smart_commute/core/config/app_config.dart';
import 'package:sg_smart_commute/core/http/json_http_client.dart';
import 'package:sg_smart_commute/core/location/location_service.dart';
import 'package:sg_smart_commute/features/places/data/onemap_place_search_repository.dart';
import 'package:sg_smart_commute/features/places/domain/place.dart';
import 'package:sg_smart_commute/features/places/domain/place_query.dart';
import 'package:sg_smart_commute/features/places/domain/place_search_session.dart';
import 'package:sg_smart_commute/features/places/place_providers.dart';

import '../../fakes/fake_environment_repository.dart';
import '../../fakes/fake_location_service.dart';
import '../../fakes/fake_place_search_repository.dart';
import '../../fakes/test_app.dart';

final vivoBody = File('test/fixtures/onemap/mall-vivocity.json')
    .readAsStringSync();

void main() {
  group('defaults come from PlaceSearchConfig', () {
    test('documented values (docs/assumptions.md)', () {
      expect(PlaceSearchConfig.debounce, const Duration(milliseconds: 350));
      expect(PlaceSearchConfig.cacheTtl, const Duration(minutes: 5));
      expect(PlaceSearchConfig.minQueryLength, 3);
      expect(PlaceSearchConfig.maxQueryLength, 100);
      expect(PlaceSearchConfig.maxCachedQueries, 50);
      expect(OneMapRateLimit.maxRequests, 1);
      expect(OneMapRateLimit.window, const Duration(seconds: 1));
    });

    test('query, session, repository and providers all default to it', () {
      expect(
        PlaceQuery.normalise('x').minLength,
        PlaceSearchConfig.minQueryLength,
      );
      final session = PlaceSearchSession(FakePlaceSearchRepository());
      addTearDown(session.dispose);
      expect(session.debounce, PlaceSearchConfig.debounce);
      expect(session.minQueryLength, PlaceSearchConfig.minQueryLength);

      final repo = OneMapPlaceSearchRepository(
        JsonHttpClient(MockClient((_) async => http.Response('{}', 200))),
        clock: DateTime.now,
      );
      expect(repo.cacheTtl, PlaceSearchConfig.cacheTtl);
      expect(repo.minQueryLength, PlaceSearchConfig.minQueryLength);

      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        container.read(placeSearchDebounceProvider),
        PlaceSearchConfig.debounce,
      );
      expect(
        container.read(placeSearchMinQueryLengthProvider),
        PlaceSearchConfig.minQueryLength,
      );
      final wired = container.read(
        placeSearchRepositoryProvider,
      ) as OneMapPlaceSearchRepository;
      expect(wired.cacheTtl, PlaceSearchConfig.cacheTtl);
      expect(wired.minQueryLength, PlaceSearchConfig.minQueryLength);
      expect(wired.maxCachedQueries, PlaceSearchConfig.maxCachedQueries);
    });
  });

  group('changing the value changes the behaviour', () {
    test('debounce: a 1 s session waits 1 s, not 350 ms', () {
      fakeAsync((async) {
        final repo = FakePlaceSearchRepository();
        final session = PlaceSearchSession(
          repo,
          debounce: const Duration(seconds: 1),
        );
        session.onChanged('VivoCity');
        async.elapse(const Duration(milliseconds: 999));
        expect(repo.queries, isEmpty);
        async.elapse(const Duration(milliseconds: 1));
        expect(repo.queries, ['vivocity']);
        session.dispose();
      });
    });

    test('minimum length: with 5, "ionor" searches and "ion" does not', () {
      fakeAsync((async) {
        final repo = FakePlaceSearchRepository();
        final session = PlaceSearchSession(repo, minQueryLength: 5);
        session.submit('ion');
        expect(session.state.value, isA<PlaceSearchTooShort>());
        expect((session.state.value as PlaceSearchTooShort).minLength, 5);
        session.submit('ionor');
        async.flushMicrotasks();
        expect(repo.queries, ['ionor']);
        // A postal code is always searchable, whatever the minimum.
        expect(
          PlaceQuery.normalise('098585', minLength: 7).isSearchable,
          isTrue,
        );
        expect(PlaceQuery.normalise('ion', minLength: 2).isSearchable, isTrue);
        session.dispose();
      });
    });

    test('repository minimum length: below it, no request is made', () async {
      var requests = 0;
      final repo = OneMapPlaceSearchRepository(
        JsonHttpClient(
          MockClient((_) async {
            requests++;
            return http.Response(vivoBody, 200);
          }),
        ),
        clock: DateTime.now,
        minQueryLength: 5,
      );
      expect(await repo.search('vivo', mode: SearchMode.submit), isEmpty);
      expect(requests, 0);
      expect(await repo.search('vivoc', mode: SearchMode.submit), hasLength(2));
      expect(requests, 1);
    });

    test('cache TTL: a 1 min cache refetches after 1 min, not 5', () async {
      var now = DateTime.utc(2026, 10, 2);
      var requests = 0;
      final repo = OneMapPlaceSearchRepository(
        JsonHttpClient(
          MockClient((_) async {
            requests++;
            return http.Response(vivoBody, 200);
          }),
        ),
        clock: () => now,
        cacheTtl: const Duration(minutes: 1),
      );
      await repo.search('VivoCity', mode: SearchMode.submit);
      now = now.add(const Duration(seconds: 59));
      await repo.search('VivoCity', mode: SearchMode.submit);
      expect(requests, 1, reason: 'still cached at 59 s');
      now = now.add(const Duration(seconds: 1));
      await repo.search('VivoCity', mode: SearchMode.submit);
      expect(requests, 2, reason: 'expired at 1 min');
    });

    test('provider wiring: an overridden minimum reaches the repository', () {
      final container = ProviderContainer(
        overrides: [placeSearchMinQueryLengthProvider.overrideWithValue(5)],
      );
      addTearDown(container.dispose);
      final repo = container.read(
        placeSearchRepositoryProvider,
      ) as OneMapPlaceSearchRepository;
      expect(repo.minQueryLength, 5);
    });

    testWidgets('search field: overridden debounce and minimum are used', (
      tester,
    ) async {
      final places = FakePlaceSearchRepository();
      await tester.pumpWidget(
        buildTestApp(
          location: FakeLocationService(access: LocationAccess.denied),
          environment: FakeEnvironmentRepository(),
          places: places,
          placeSearchDebounce: const Duration(seconds: 1),
          placeSearchMinQueryLength: 5,
        ),
      );
      await tester.pump();
      const field = Key('manual-origin-field');

      await tester.enterText(find.byKey(field), 'vivo');
      await tester.pump();
      expect(
        find.text('Type at least 5 characters, or a 6-digit postal code.'),
        findsOneWidget,
      );

      await tester.enterText(find.byKey(field), 'VivoCity');
      await tester.pump(const Duration(milliseconds: 400));
      expect(places.queries, isEmpty, reason: 'the 350 ms default is not used');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(places.queries, ['vivocity']);
      expect(find.text('VIVOCITY'), findsOneWidget);
    });
  });
}
