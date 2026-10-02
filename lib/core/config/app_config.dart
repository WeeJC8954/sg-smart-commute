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
  static Uri search(String query) =>
      Uri.https('www.onemap.gov.sg', '/api/common/elastic/search', {
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

  /// Per-request HTTP timeout (§15).
  static const Duration httpTimeout = Duration(seconds: 10);

  /// Minimum gap between accepted "Refresh all" taps (a UX debounce). The
  /// data.gov.sg limit itself is enforced for every caller by the shared
  /// limiter ([DataGovSgRateLimit]), not by this cooldown.
  static const Duration minEnvironmentRefreshInterval = Duration(seconds: 15);
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

/// Bundled MRT station asset (generated by tool/build_mrt_asset.dart).
const String mrtStationsAsset = 'assets/mrt_stations.json';

const String busrouterAttribution = 'Bus data: busrouter.sg (data © LTA)';
const String mrtAttribution =
    'MRT exits: LTA via data.gov.sg (Singapore Open Data Licence)';
