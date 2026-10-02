/// Non-secret configuration (guide v2.1 §14). Nothing here is confidential:
/// it all ships in the Web bundle and the APK.
library;

/// Singapore bounding box (guide §5.2, docs/assumptions.md). Inclusive.
abstract final class SgBounds {
  static const double minLatitude = 1.15;
  static const double maxLatitude = 1.48;
  static const double minLongitude = 103.60;
  static const double maxLongitude = 104.10;
}

/// data.gov.sg v2 real-time endpoints (keyless, CORS `*`; docs/api-feasibility.md).
abstract final class NeaEndpoints {
  static const String _base = 'https://api-open.data.gov.sg/v2/real-time/api';
  static final Uri twoHourForecast = Uri.parse('$_base/two-hr-forecast');
  static final Uri uv = Uri.parse('$_base/uv');
  static final Uri pm25 = Uri.parse('$_base/pm25');
  static final Uri psi = Uri.parse('$_base/psi');
}

/// OneMap (Singapore Land Authority) search, used tokenless (docs/api-feasibility.md
/// §4). Tokenless access is undocumented and may be withdrawn: a 401/403 is
/// surfaced as `ApiUnauthorized`, never worked around. Reverse geocoding
/// (`/api/public/revgeocode`) answers 401 without a token, so it is not used.
abstract final class OneMapEndpoints {
  static const String host = 'www.onemap.gov.sg';

  static Uri search(String query) =>
      Uri.https(host, '/api/common/elastic/search', {
        'searchVal': query,
        'returnGeom': 'Y',
        'getAddrDetails': 'Y',
        'pageNum': '1',
      });
}

/// Place-search tunables (guide v2.1 §8.3, §15; docs/assumptions.md). The single
/// source for these values.
abstract final class PlaceSearchConfig {
  /// Type-ahead waits this long after the last keystroke; submit is immediate.
  static const Duration debounce = Duration(milliseconds: 350);

  /// Successful results are cached in memory per normalised query this long.
  static const Duration cacheTtl = Duration(minutes: 5);

  /// Shorter queries are not searched, unless they are a 6-digit postal code.
  static const int minQueryLength = 3;

  /// The search field accepts at most this many characters, and a longer
  /// query (e.g. pasted) is cut to it before it is sent. Real addresses and
  /// place names are far shorter.
  static const int maxQueryLength = 100;

  /// At most this many queries' results are cached; the least recently used
  /// is evicted first, and expired entries are dropped on every write.
  static const int maxCachedQueries = 50;
}

/// Client-side pacing of OneMap requests (docs/assumptions.md, "OneMap rate
/// limit"). OneMap publishes no number; this is a conservative pace below
/// what was observed to draw a 429 (2–3 calls within about 1.5 s). Every send
/// waits for a grant, retries included.
abstract final class OneMapRateLimit {
  static const int maxRequests = 1;
  static const Duration window = Duration(seconds: 1);

  static bool appliesTo(Uri uri) => uri.host == OneMapEndpoints.host;
}

/// Attribution shown wherever OneMap search results appear.
const String oneMapAttribution =
    'Place search: OneMap © Singapore Land Authority';

/// data.gov.sg anonymous limit for the v2 real-time API: 6 calls in any 10 s
/// (docs/api-feasibility.md). It is enforced client-side by one shared
/// rolling-window limiter, so every caller is covered.
abstract final class DataGovSgRateLimit {
  static const String host = 'api-open.data.gov.sg';
  static const String realTimePathPrefix = '/v2/real-time/';

  static const int maxRequests = 6;
  static const Duration window = Duration(seconds: 10);

  /// Added to [window] because the server counts arrival times, and network
  /// latency varies: calls sent 10 s apart can arrive less than 10 s apart.
  static const Duration safetyMargin = Duration(seconds: 1);

  static bool appliesTo(Uri uri) =>
      uri.host == host && uri.path.startsWith(realTimePathPrefix);
}

abstract final class AppTimings {
  /// Location acquisition timeout, started once permission is granted (§5.1).
  static const Duration locationTimeout = Duration(seconds: 10);

  /// The permission step's own bound: an unanswered prompt (a browser's
  /// location prompt never resolves on its own) falls back to manual entry
  /// after this, while the attempt keeps waiting for an answer.
  static const Duration locationPermissionTimeout = Duration(seconds: 10);

  /// Per-request HTTP timeout (§15).
  static const Duration httpTimeout = Duration(seconds: 10);

  /// Bounded HTTP retry (§15), for network errors and 5xx only: at most this
  /// many retries after the first attempt.
  static const int httpMaxRetries = 2;

  /// Backoff before retry n (0-based) is this × 2^n: 500 ms, then 1 s.
  static const Duration httpBaseBackoff = Duration(milliseconds: 500);

  /// Minimum gap between accepted "Refresh all" taps (a UX debounce). The
  /// data.gov.sg limit itself is enforced for every caller by the shared
  /// limiter ([DataGovSgRateLimit]), not by this cooldown.
  static const Duration minEnvironmentRefreshInterval = Duration(seconds: 15);

  /// How often time-relative text is recomputed while the screen is open
  /// ("N min ago", Stale, the UV night rule, bus ETAs). A UI-only rebuild: it
  /// never sends a request, so there is still no automatic polling.
  static const Duration uiTick = Duration(seconds: 15);
}

/// Home-screen layout (presentation only; docs/assumptions.md, "Conditions
/// grid"). Widths are logical pixels at text scale 1.0; the tile minimums grow
/// with the text scale, so large text falls back to fewer columns.
abstract final class HomeLayout {
  /// Origin, destination and journey cards, and the page on narrow screens.
  static const double contentMaxWidth = 640;

  /// The Conditions section may grow to this on wide screens (4 across).
  static const double conditionsMaxWidth = 1080;

  /// Narrowest tile in the 2-column grid. Below 2 × this + [gridGap], the
  /// tiles stack in one column.
  static const double minTileWidth = 150;

  /// Narrowest tile when all four sit in one row (wide Web).
  static const double minWideTileWidth = 220;

  static const double gridGap = 8;
}

/// Stale thresholds (§6.3, docs/assumptions.md).
abstract final class StaleAfter {
  static const Duration twoHourForecast = Duration(hours: 3);
  static const Duration pm25 = Duration(hours: 2);
  static const Duration psi = Duration(hours: 2);
  static const Duration uvDaytime = Duration(hours: 2);
}

/// UV is measured roughly 07:00–19:00 SGT. Outside [uvDayStartHour,
/// uvDayEndHour) the last reading is shown as "not measured at night".
abstract final class UvHours {
  static const int uvDayStartHour = 7;
  static const int uvDayEndHour = 20;
}

const String neaSourceLabel = 'NEA / data.gov.sg';

/// busrouter.sg static bus data (guide v2.1 §9.1; docs/data-sources.md).
/// Loaded once per session on the first journey request.
abstract final class BusrouterEndpoints {
  static final Uri stops = Uri.parse(
    'https://data.busrouter.sg/v1/stops.min.json',
  );
  static final Uri services = Uri.parse(
    'https://data.busrouter.sg/v1/services.min.json',
  );
}

/// Transport-dataset coordinate sanity range. Wider than [SgBounds], which
/// validates the user's location: a few bus stops lie across the Causeway
/// (e.g. 46239 Larkin Ter at latitude 1.4955). Distance filtering keeps them
/// out of ordinary Singapore journeys.
abstract final class TransportDataBounds {
  static const double minLatitude = 1.10;
  static const double maxLatitude = 1.60;
  static const double minLongitude = 103.50;
  static const double maxLongitude = 104.20;
}

/// busrouter payload validation (docs/assumptions.md, "busrouter validation").
abstract final class BusrouterValidation {
  /// The whole stops or services dataset fails when more than this share of
  /// its entries is malformed: that points at a schema change, not a stray
  /// record.
  static const double maxInvalidShare = 0.05;
}

/// Direct-bus planner and walking estimate (guide v2.1 §9.2, §9.3). These are
/// documented heuristic assumptions (docs/assumptions.md), not official values.
abstract final class JourneyConfig {
  /// Candidate-stop radius around origin and destination.
  static const double stopRadiusMeters = 400;

  /// Used once if the first radius yields no direct match.
  static const double widenedStopRadiusMeters = 800;

  /// Straight-line distance × this factor approximates the street network.
  static const double walkDetourFactor = 1.3;

  /// About 4.8 km/h.
  static const double walkMetersPerMinute = 80;

  /// score = walk to stop (min) + walk from stop (min) + this × stops.
  static const double stopWeight = 1.5;

  /// One "Suggested" option plus up to two alternatives.
  static const int maxOptions = 3;

  /// At or below this straight-line distance, suggest walking instead.
  static const double walkOnlyMaxMeters = 300;

  /// Beyond this, no MRT station is suggested as "nearest".
  static const double mrtMaxDistanceMeters = 1500;
}

/// ArriveLah live bus arrivals (guide v2.1 §10; docs/data-sources.md). A
/// community proxy of LTA DataMall Bus Arrival: keyless, `ACAO: *`, no SLA.
abstract final class ArriveLahEndpoints {
  static const String base = 'https://arrivelah2.busrouter.sg/';

  /// One request per bus stop; it lists every service calling there.
  static Uri forStop(String busStopCode) =>
      Uri.parse(base).replace(queryParameters: {'id': busStopCode});
}

/// Live bus arrivals (guide v2.1 §10, §15; docs/assumptions.md).
abstract final class BusArrivalConfig {
  /// A stop's arrivals are reused for this long; repeated Refresh taps inside
  /// it make no request. ArriveLah itself answers with `max-age=15`, so a
  /// sooner request would only return the same cached response.
  static const Duration cacheTtl = Duration(seconds: 15);

  /// An estimated arrival at most this far ahead (or already past) is shown
  /// as "Arr".
  static const Duration arrivingWithin = Duration(minutes: 1);

  /// Next buses shown per displayed service (ArriveLah gives up to three).
  static const int maxShown = 3;

  /// An estimate further in the past than this is dropped as "no time": the
  /// bus has left, or the response is a replayed old one. Up to this, it is
  /// shown as "Arr" (the bus may still be at the stop).
  static const Duration maxPastEta = Duration(minutes: 2);

  /// An estimate further ahead than this is dropped as "no time": LTA lists
  /// the next three buses, never hours ahead, so it is bogus.
  static const Duration maxFutureEta = Duration(hours: 3);

  /// ETAs count down from the clock between checks. Once a check is older
  /// than this, the minutes are replaced by a prompt to refresh, because the
  /// buses' estimates have moved on since.
  static const Duration outdatedAfter = Duration(minutes: 3);
}

/// Bundled MRT station asset (generated by tool/build_mrt_asset.dart).
const String mrtStationsAsset = 'assets/mrt_stations.json';

const String busrouterAttribution = 'Bus data: busrouter.sg (data © LTA)';
const String arriveLahAttribution = 'Arrivals: ArriveLah (LTA DataMall)';
const String mrtAttribution =
    'MRT exits: LTA via data.gov.sg (Singapore Open Data Licence)';
