import '../../../core/config/app_config.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/geo/geo.dart';
import '../domain/place.dart';
import '../domain/place_query.dart';

/// Maps a OneMap elastic-search response to [Place]s (guide v2.1 §8).
///
/// Tokenless responses always carry `"error": "Authentication token
/// missing…"`, even for genuine no-result queries (`000000`). So `error` with
/// a `results` list is normal: the list decides. A response with no `results`
/// list at all, but with an `error`, is treated as the provider refusing
/// (`ApiUnauthorized`). Anything else malformed is `InvalidApiResponse`.
///
/// Results with missing, invalid or out-of-Singapore coordinates are dropped.
List<Place> parseOneMapSearch(Object? json) {
  if (json is! Map<String, dynamic>) {
    throw const InvalidApiResponse('OneMap: body is not an object');
  }
  final results = json['results'];
  if (results == null) {
    if (json['error'] != null) throw const ApiUnauthorized();
    throw const InvalidApiResponse('OneMap: no results field');
  }
  if (results is! List) {
    throw const InvalidApiResponse('OneMap: results is not a list');
  }

  final places = <Place>[];
  for (final item in results.take(PlaceSearchConfig.maxResults)) {
    if (item is! Map<String, dynamic>) continue;
    final place = _toPlace(item);
    if (place != null) places.add(place);
  }
  return places;
}

Place? _toPlace(Map<String, dynamic> r) {
  final name = _clean(r['SEARCHVAL']);
  final lat = double.tryParse(_clean(r['LATITUDE']) ?? '');
  final lng = double.tryParse(_clean(r['LONGITUDE']) ?? '');
  if (name == null || lat == null || lng == null) return null;
  if (!isWithinSingapore(LatLng(lat, lng))) return null;

  final postal = _clean(r['POSTAL']);
  final building = _clean(r['BUILDING']);
  final block = _clean(r['BLK_NO']);
  return Place(
    id: 'onemap:$name@$lat,$lng',
    displayName: name,
    address: _clean(r['ADDRESS']),
    postalCode: postal != null && isPostalCode(postal) ? postal : null,
    latitude: lat,
    longitude: lng,
    type: _typeOf(name: name, building: building, block: block),
    source: PlaceSource.oneMap,
  );
}

/// OneMap does not say what a result is. Only what the fields show reliably
/// is inferred; malls and POIs are not told apart from other buildings.
PlaceType _typeOf({
  required String name,
  required String? building,
  required String? block,
}) {
  final upper = name.toUpperCase();
  if (upper.contains('MRT STATION') || upper.contains('LRT STATION')) {
    return PlaceType.mrtStation;
  }
  if (building != null) return PlaceType.building;
  return PlaceType.address; // an HDB block / street address, or a road
}

/// OneMap uses "NIL" (and sometimes "") for missing values.
String? _clean(Object? value) {
  if (value is! String) return null;
  final v = value.trim();
  if (v.isEmpty || v.toUpperCase() == 'NIL') return null;
  return v;
}
