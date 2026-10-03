import '../../../core/geo/geo.dart';

/// Place model and search interface (guide v2.1 §8.1).
enum PlaceType {
  postalCode,
  address,
  building,
  mall,
  poi,
  mrtStation,
  busStop,
  other,
}

enum PlaceSource { oneMap, photon, nominatim, bundled }

/// Type-ahead (debounced, while typing) or an explicit submit (§8.2, §8.3).
enum SearchMode { typeahead, submit }

class Place {
  const Place({
    required this.id,
    required this.displayName,
    required this.latitude,
    required this.longitude,
    required this.type,
    required this.source,
    this.address,
    this.postalCode,
  });

  /// Provider-scoped identifier.
  final String id;
  final String displayName;
  final String? address;

  /// Always a string: Singapore postal codes may start with 0 (`098585`).
  final String? postalCode;
  final double latitude;
  final double longitude;
  final PlaceType type;

  /// The adapter that found it (guide v2.1 §8.1 model). Only OneMap is built,
  /// so nothing reads it yet.
  final PlaceSource source;

  LatLng get position => LatLng(latitude, longitude);

  /// [address], unless it only repeats [displayName] (OneMap names HDB blocks
  /// by their full address). Null when there is no distinct address, so it is
  /// never shown twice.
  String? get distinctAddress => address == displayName ? null : address;

  @override
  String toString() => 'Place($displayName, $postalCode)';
}

abstract interface class PlaceSearchRepository {
  /// Places matching [query], best first, all inside Singapore. Empty when
  /// nothing matches. Throws an [AppFailure] (e.g. `NoExactPostalMatch`,
  /// `ApiUnauthorized`, `NetworkUnavailable`, `InvalidApiResponse`).
  Future<List<Place>> search(String query, {required SearchMode mode});

  /// The place at a position, or null when the provider cannot resolve it.
  Future<Place?> reverseGeocode(double latitude, double longitude);
}
