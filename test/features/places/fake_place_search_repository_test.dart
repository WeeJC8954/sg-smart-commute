// The fake's opt-in prefix matching (synthetic demo app only): off by
// default, so every other test keeps exact matching.
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/core/errors/app_failure.dart';
import 'package:sg_smart_commute/features/places/domain/place.dart';

import '../../../integration_test/fakes/fake_place_search_repository.dart';

void main() {
  Future<List<Place>> find(FakePlaceSearchRepository repo, String query) =>
      repo.search(query, mode: SearchMode.typeahead);

  test('off by default: a partial query finds nothing', () async {
    final repo = FakePlaceSearchRepository();
    expect(repo.prefixMatch, isFalse);
    expect(await find(repo, 'bay'), isEmpty);
    expect(await find(repo, 'bay mal'), isEmpty);
    expect(await find(repo, 'Bay Mall'), [fakeBayMall]);
  });

  test('on: the start of a key finds its places', () async {
    final repo = FakePlaceSearchRepository(prefixMatch: true);
    expect(await find(repo, 'bay'), [fakeBayMall]);
    expect(await find(repo, 'bay mal'), [fakeBayMall]);
    expect(await find(repo, '  BAY   mal '), [fakeBayMall]);
    expect(await find(repo, '0099'), [fakeBayMall]);
    expect(await find(repo, 'north'), [fakeNorthMrtA, fakeNorthMrtB]);
    expect(repo.queries, ['bay', 'bay mal', 'bay mal', '0099', 'north']);
  });

  test(
    'on: no substring or word match, and no answer to an empty query',
    () async {
      final repo = FakePlaceSearchRepository(prefixMatch: true);
      expect(await find(repo, 'mall'), isEmpty);
      expect(await find(repo, 'ay mall'), isEmpty);
      expect(await find(repo, ''), isEmpty);
    },
  );

  test('on: exact queries answer as before, and an exact key wins', () async {
    final repo = FakePlaceSearchRepository(prefixMatch: true);
    expect(await find(repo, 'bay mall'), [fakeBayMall]);
    expect(await find(repo, '009902'), [fakeBayMall]);
    expect(await find(repo, 'north mrt'), [fakeNorthMrtA, fakeNorthMrtB]);
    expect(await find(repo, 'nowhere'), isEmpty);

    final shadowed = FakePlaceSearchRepository(
      prefixMatch: true,
      results: {
        'bay': [],
        'bay mall': [fakeBayMall],
      },
    );
    expect(await find(shadowed, 'bay'), isEmpty);
  });

  test('on: places under several keys come once, in key order', () async {
    final repo = FakePlaceSearchRepository(
      prefixMatch: true,
      results: {
        'city tower': [fakeCityTower],
        'city': [fakeEastHub, fakeCityTower],
        'city tower east': [fakeEastHub, fakeBayMall],
      },
    );
    expect(await find(repo, 'cit'), [fakeCityTower, fakeEastHub, fakeBayMall]);
  });

  test('on: failures and held queries stay exact', () async {
    final repo = FakePlaceSearchRepository(
      prefixMatch: true,
      failures: {'bay mall': const NetworkUnavailable()},
    );
    expect(await find(repo, 'bay'), [fakeBayMall]);
    await expectLater(
      find(repo, 'bay mall'),
      throwsA(isA<NetworkUnavailable>()),
    );

    repo.hold('bay mal');
    var released = false;
    final held = find(repo, 'bay mal').then((r) {
      released = true;
      return r;
    });
    expect(await find(repo, 'bay'), [fakeBayMall], reason: 'not held');
    await Future<void>.delayed(Duration.zero);
    expect(released, isFalse);
    repo.release('bay mal');
    expect(await held, [fakeBayMall]);
  });
}
