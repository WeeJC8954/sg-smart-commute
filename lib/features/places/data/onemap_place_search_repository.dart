import '../../../core/config/app_config.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/http/json_http_client.dart';
import '../../../core/time/clock.dart';
import '../domain/place.dart';
import '../domain/place_query.dart';
import 'onemap_parser.dart';

/// OneMap tokenless search behind [PlaceSearchRepository] (guide v2.1 §8.2).
///
/// - Queries are normalised first ([PlaceQuery.normalise]).
/// - A 6-digit postal-code query only returns results with exactly that
///   postcode. If OneMap returned results but none match exactly, the search
///   throws [NoExactPostalMatch].
/// - Successful results are cached in memory per normalised query for
///   [cacheTtl], for at most [maxCachedQueries] queries (least recently used
///   evicted first; expired entries dropped on every write). Failures are not
///   cached.
/// - [reverseGeocode] returns null without a network call. OneMap's reverse
///   geocoder answers 401 without a token, and no credential is used.
///
/// Timeout, bounded retry, 401/403 → `ApiUnauthorized` and 429 come from
/// [JsonHttpClient]. Photon / Nominatim / bundled fallbacks are contingency
/// providers and are not built (§0.1 item 6).
class OneMapPlaceSearchRepository implements PlaceSearchRepository {
  OneMapPlaceSearchRepository(
    this._http, {
    required this.clock,
    this.cacheTtl = PlaceSearchConfig.cacheTtl,
    this.minQueryLength = PlaceSearchConfig.minQueryLength,
    this.maxCachedQueries = PlaceSearchConfig.maxCachedQueries,
  }) : assert(maxCachedQueries > 0);

  final JsonHttpClient _http;
  final Clock clock;
  final Duration cacheTtl;

  /// Shorter non-postal-code queries return [] without a request.
  final int minQueryLength;

  final int maxCachedQueries;

  /// Insertion-ordered (Dart's default map), oldest use first: a hit is moved
  /// to the end, so the first entry is the least recently used.
  final Map<String, ({DateTime at, List<Place> places})> _cache = {};

  /// Number of cached queries (for tests).
  int get cachedQueryCount => _cache.length;

  @override
  Future<List<Place>> search(String query, {required SearchMode mode}) async {
    // OneMap has no separate submit endpoint; both modes use the same call.
    final q = PlaceQuery.normalise(query, minLength: minQueryLength);
    if (!q.isSearchable) return const [];

    final cached = _cache.remove(q.text);
    if (cached != null && clock().difference(cached.at) < cacheTtl) {
      _cache[q.text] = cached; // now the most recently used
      return cached.places;
    }

    final places = parseOneMapSearch(
      await _http.getJson(OneMapEndpoints.search(q.text)),
    );
    final result = q.isPostalCode ? _exactPostal(q.text, places) : places;
    _store(q.text, result);
    return result;
  }

  void _store(String query, List<Place> places) {
    final now = clock();
    _cache
      ..remove(query)
      ..removeWhere((_, e) => now.difference(e.at) >= cacheTtl);
    while (_cache.length >= maxCachedQueries) {
      _cache.remove(_cache.keys.first);
    }
    _cache[query] = (at: now, places: places);
  }

  static List<Place> _exactPostal(String postal, List<Place> places) {
    final exact = places.where((p) => p.postalCode == postal).toList();
    if (exact.isEmpty && places.isNotEmpty) throw NoExactPostalMatch(postal);
    return exact;
  }

  @override
  Future<Place?> reverseGeocode(double latitude, double longitude) async =>
      null;
}
