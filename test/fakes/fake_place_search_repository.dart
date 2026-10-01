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

final vivoCity = fakePlace(
  'VIVOCITY',
  lat: 1.2643,
  lng: 103.8223,
  address: '1 HARBOURFRONT WALK VIVOCITY SINGAPORE 098585',
  postal: '098585',
);
final ionOrchard = fakePlace(
  'ION ORCHARD',
  lat: 1.3040,
  lng: 103.8320,
  address: '2 ORCHARD TURN ION ORCHARD SINGAPORE 238801',
  postal: '238801',
);
final tampinesHub = fakePlace(
  'OUR TAMPINES HUB',
  lat: 1.3530,
  lng: 103.9405,
  address: '1 TAMPINES WALK OUR TAMPINES HUB SINGAPORE 528523',
  postal: '528523',
);
final bishanMrtCc = fakePlace(
  'BISHAN MRT STATION (CC15)',
  lat: 1.3513,
  lng: 103.8491,
  address: '17 BISHAN PLACE BISHAN MRT STATION (CC15) SINGAPORE 579842',
  postal: '579842',
  type: PlaceType.mrtStation,
);
final bishanMrtNs = fakePlace(
  'BISHAN MRT STATION (NS17)',
  lat: 1.3510,
  lng: 103.8483,
  address: '200 BISHAN ROAD BISHAN MRT STATION (NS17) SINGAPORE 579827',
  postal: '579827',
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
    'vivocity': [vivoCity],
    '098585': [vivoCity],
    'ion orchard': [ionOrchard],
    '238801': [ionOrchard],
    'tampines hub': [tampinesHub],
    'bishan mrt': [bishanMrtCc, bishanMrtNs],
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
