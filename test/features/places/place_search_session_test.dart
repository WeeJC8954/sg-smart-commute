import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/core/errors/app_failure.dart';
import 'package:sg_smart_commute/features/places/domain/place_search_session.dart';

import '../../fakes/fake_place_search_repository.dart';

const debounce = Duration(milliseconds: 350);

void main() {
  late FakePlaceSearchRepository repo;
  late PlaceSearchSession session;

  setUp(() {
    repo = FakePlaceSearchRepository(
      results: {
        'viv': [vivoCity, ionOrchard],
        'vivocity': [vivoCity],
        'bishan mrt': [bishanMrtCc, bishanMrtNs],
      },
      failures: {'offline': const NetworkUnavailable()},
    );
    session = PlaceSearchSession(repo, debounce: debounce);
  });

  PlaceSearchState state() => session.state.value;

  test('type-ahead waits for the debounce, then searches once', () {
    fakeAsync((async) {
      session.onChanged('v');
      session.onChanged('vi');
      session.onChanged('viv');
      expect(state(), isA<PlaceSearchLoading>());
      async.elapse(debounce - const Duration(milliseconds: 1));
      expect(repo.queries, isEmpty);
      async.elapse(const Duration(milliseconds: 1));
      async.flushMicrotasks();
      expect(repo.queries, ['viv']);
      expect((state() as PlaceSearchResults).places, [vivoCity, ionOrchard]);
    });
  });

  test('too short → no search; empty → idle', () {
    fakeAsync((async) {
      session.onChanged('vi');
      expect(state(), isA<PlaceSearchTooShort>());
      session.onChanged('   ');
      expect(state(), isA<PlaceSearchIdle>());
      async.elapse(const Duration(seconds: 1));
      expect(repo.queries, isEmpty);
    });
  });

  test('submit searches immediately, without the debounce', () {
    fakeAsync((async) {
      session.submit('VivoCity');
      async.flushMicrotasks();
      expect(repo.queries, ['vivocity']);
      expect(state(), isA<PlaceSearchResults>());
    });
  });

  test('race: an older, slower response never replaces a newer query', () {
    fakeAsync((async) {
      repo.hold('viv');
      session.onChanged('viv');
      async.elapse(debounce); // "viv" is now in flight, held
      session.onChanged('vivocity');
      async.elapse(debounce);
      async.flushMicrotasks();
      expect((state() as PlaceSearchResults).query, 'vivocity');
      expect((state() as PlaceSearchResults).places, [vivoCity]);

      repo.release('viv'); // the stale answer arrives last
      async.flushMicrotasks();
      expect((state() as PlaceSearchResults).query, 'vivocity');
      expect((state() as PlaceSearchResults).places, [vivoCity]);
      expect(repo.queries, ['viv', 'vivocity']);
    });
  });

  test('race: a stale response does not replace "loading" for a newer one', () {
    fakeAsync((async) {
      repo.hold('viv');
      repo.hold('vivocity');
      session.submit('viv');
      session.submit('vivocity');
      repo.release('viv');
      async.flushMicrotasks();
      expect(state(), isA<PlaceSearchLoading>());
      expect((state() as PlaceSearchLoading).query, 'vivocity');
      repo.release('vivocity');
      async.flushMicrotasks();
      expect((state() as PlaceSearchResults).places, [vivoCity]);
    });
  });

  test('clear() drops an in-flight response', () {
    fakeAsync((async) {
      repo.hold('vivocity');
      session.submit('vivocity');
      session.clear();
      repo.release('vivocity');
      async.flushMicrotasks();
      expect(state(), isA<PlaceSearchIdle>());
    });
  });

  test('several results are listed, never auto-selected', () {
    fakeAsync((async) {
      session.submit('Bishan MRT');
      async.flushMicrotasks();
      final results = state() as PlaceSearchResults;
      expect(results.places, hasLength(2));
      // The session has no notion of a selection: only the UI's tap selects.
    });
  });

  test('no results → empty result list (not a failure)', () {
    fakeAsync((async) {
      session.submit('nowhere at all');
      async.flushMicrotasks();
      expect((state() as PlaceSearchResults).places, isEmpty);
    });
  });

  test('failure → PlaceSearchFailed; retry repeats the last query', () {
    fakeAsync((async) {
      session.submit('offline');
      async.flushMicrotasks();
      expect((state() as PlaceSearchFailed).failure, isA<NetworkUnavailable>());
      repo.failures.remove('offline');
      repo.results['offline'] = [vivoCity];
      session.retry();
      async.flushMicrotasks();
      expect((state() as PlaceSearchResults).places, [vivoCity]);
      expect(repo.queries, ['offline', 'offline']);
    });
  });
}
