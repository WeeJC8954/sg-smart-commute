import 'dart:async';

import 'package:sg_smart_commute/core/errors/app_failure.dart';
import 'package:sg_smart_commute/features/places/domain/place.dart';
import 'package:sg_smart_commute/features/places/domain/place_query.dart';

Place fakePlace(
  String name, {
  required double lat,
  required double lng,
  String? address,
  String? postal,
  PlaceType type = PlaceType.building,
}) => Place(
  id: 'fake:$name',
  displayName: name,
  address: address,
  postalCode: postal,
  latitude: lat,
  longitude: lng,
  type: type,
  source: PlaceSource.oneMap,
);

// Synthetic places (owner decision of 2026-11-07, integration_test/fakes/
// README_places.md). Nothing is copied from OneMap or any other source:
// names end in "(fake)", roads are FAKE ..., postcodes are in the unused
// sectors 00 and 99, and positions are round numbers chosen so that the fake
// bus network (fake_bus_network.dart) gives the journeys the tests expect.

/// A mall south-west of the fake GPS fix; Bishan → here is the main fake
/// journey (three direct buses). Its postcode starts with 0.
final fakeBayMall = fakePlace(
  'BAY MALL (fake)',
  lat: 1.3000,
  lng: 103.7750,
  address: '1 FAKE WALK BAY MALL (fake) SINGAPORE 009902',
  postal: '009902',
);

/// One stop by bus (F30) from the fix.
final fakeCityTower = fakePlace(
  'CITY TOWER (fake)',
  lat: 1.3200,
  lng: 103.8100,
  address: '2 FAKE TURN CITY TOWER (fake) SINGAPORE 990802',
  postal: '990802',
);

/// In the east: nearest the fake "Tampines" forecast area and the east
/// region; no direct bus to [fakeCityTower].
final fakeEastHub = fakePlace(
  'EAST HUB (fake)',
  lat: 1.3650,
  lng: 103.9250,
  address: '1 FAKE LANE EAST HUB (fake) SINGAPORE 990803',
  postal: '990803',
);

/// Two coded platforms of one station, both within 300 m of the fix.
final fakeNorthMrtA = fakePlace(
  'NORTH MRT STATION (FN1) (fake)',
  lat: 1.3515,
  lng: 103.8480,
  address: '17 FAKE ROAD NORTH MRT STATION (FN1) (fake) SINGAPORE 990811',
  postal: '990811',
  type: PlaceType.mrtStation,
);
final fakeNorthMrtB = fakePlace(
  'NORTH MRT STATION (FN2) (fake)',
  lat: 1.3505,
  lng: 103.8490,
  address: '200 FAKE ROAD NORTH MRT STATION (FN2) (fake) SINGAPORE 990812',
  postal: '990812',
  type: PlaceType.mrtStation,
);

/// Controllable [PlaceSearchRepository] for widget and integration tests.
///
/// Answers by normalised query from [results] (missing → no results), or
/// throws the failure in [failures]. A query listed in [held] waits until the
/// test calls [release], so the test decides the order responses arrive in.
class FakePlaceSearchRepository implements PlaceSearchRepository {
  FakePlaceSearchRepository({
    Map<String, List<Place>>? results,
    Map<String, AppFailure>? failures,
  }) : results = results ?? defaultResults,
       failures = failures ?? {};

  static final Map<String, List<Place>> defaultResults = {
    'bay mall': [fakeBayMall],
    '009902': [fakeBayMall],
    'city tower': [fakeCityTower],
    '990802': [fakeCityTower],
    'east hub': [fakeEastHub],
    'north mrt': [fakeNorthMrtA, fakeNorthMrtB],
  };

  final Map<String, List<Place>> results;
  final Map<String, AppFailure> failures;
  final List<String> queries = [];
  final Map<String, Completer<void>> _held = {};

  void hold(String query) => _held[query.toLowerCase()] = Completer<void>();
  void release(String query) => _held.remove(query.toLowerCase())?.complete();

  @override
  Future<List<Place>> search(String query, {required SearchMode mode}) async {
    final key = PlaceQuery.normalise(query).text.toLowerCase();
    queries.add(key);
    final gate = _held[key];
    if (gate != null) await gate.future;
    final failure = failures[key];
    if (failure != null) throw failure;
    return results[key] ?? const [];
  }

  @override
  Future<Place?> reverseGeocode(double latitude, double longitude) async =>
      null;
}
