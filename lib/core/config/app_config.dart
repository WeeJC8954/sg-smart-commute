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

  /// Only this many results of a response are read: OneMap's page 1 has at
  /// most 10, and every result is built into the list at once (#59).
  static const int maxResults = 10;
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

/// OneMap raster basemap (Singapore Land Authority), accepted in P2-M0
/// (docs/map-feasibility.md §4.2): keyless, CORS `*`, no service-level
/// agreement and no published volume limit, so [MapConfig] keeps the
/// project's own reasonable-use bounds. Same host as search, so it adds no
/// CSP origin.
abstract final class BasemapEndpoints {
  static const String host = OneMapEndpoints.host;

  /// Light basemap.
  static const String defaultTiles =
      'https://$host/maps/tiles/Default/{z}/{x}/{y}.png';

  /// Dark basemap.
  static const String nightTiles =
      'https://$host/maps/tiles/Night/{z}/{x}/{y}.png';

  /// The OneMap logo the attribution must show (20 × 20).
  static final Uri logo = Uri.https(
    host,
    '/web-assets/images/logo/om_logo.png',
  );

  /// Attribution links, from OneMap's snippet
  /// (`docs/maps/resources/code-attr.txt`).
  static final Uri oneMapSite = Uri.https(host, '/');
  static final Uri slaSite = Uri.https('www.sla.gov.sg', '/');
}

/// The required basemap attribution text, shown after the OneMap logo
/// whenever tiles are on screen; "OneMap" and "Singapore Land Authority" are
/// links ([BasemapEndpoints.oneMapSite], [BasemapEndpoints.slaSite]).
abstract final class BasemapAttribution {
  static const String oneMap = 'OneMap';
  static const String contributors = ' © contributors | ';
  static const String sla = 'Singapore Land Authority';
  static const String full = '$oneMap$contributors$sla';
}

/// Journey map (P2-M1; docs/map-feasibility.md §4.2 reasonable-use rules,
/// docs/assumptions.md "Journey map").
abstract final class MapConfig {
  /// OneMap's documented zoom range; no tiles are requested outside it.
  static const double minZoom = 11;
  static const double maxZoom = 19;

  /// OneMap's documented basemap bounds. The camera cannot leave them, so
  /// no tiles outside Singapore are requested.
  static const double boundsSouth = 1.144;
  static const double boundsWest = 103.535;
  static const double boundsNorth = 1.494;
  static const double boundsEast = 104.502;

  /// Fitting the camera to the markers never zooms closer than this, so two
  /// close points keep some street context.
  static const double fitMaxZoom = 17;

  /// Space kept between the markers and the map's edges when fitting.
  static const double fitPadding = 48;

  /// Height of the map on the home screen.
  static const double height = 280;

  /// Android tile cache cap (flutter_map's built-in cache, which follows the
  /// tiles' `Cache-Control`). The Web relies on the browser's HTTP cache.
  static const int tileCacheMaxBytes = 50 * 1000 * 1000;

  /// Sent as the tile requests' User-Agent on Android (not settable on Web).
  static const String userAgentPackageName = 'sg.smartcommute.sg_smart_commute';

  /// Bus ride line (P2-M2; docs/assumptions.md "Bus ride line"): a ride stop
  /// matches the route line within this distance.
  static const double rideStopToleranceMeters = 60;

  /// Positions of one stop closer than this along the line are one pass.
  static const double rideCandidateMergeMeters = 40;

  /// A hop longer than this × its straight line is not trusted…
  static const double rideMaxDetour = 3.0;

  /// …when the straight line is longer than this (very short hops are noisy).
  static const double rideDetourMinStraightMeters = 50;

  /// Walking connectors (P2-M3; docs/assumptions.md "Walking connectors and
  /// legend"): one shorter than this is not drawn (its two ends are the same
  /// place, e.g. a destination at the stop itself).
  static const double walkConnectorMinMeters = 1;
}

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

  /// Longest `Retry-After` honoured after a 429; a longer one is cut to
  /// this, so a bad header cannot lock a provider out for the session.
  static const Duration maxRetryAfter = Duration(seconds: 60);

  /// Largest response body accepted from any provider. The biggest real one
  /// is busrouter `stops.min.json` (~317 KB decoded, 2026-10-02), so this
  /// leaves > 12× headroom while bounding a runaway response.
  static const int httpMaxResponseBytes = 4 * 1024 * 1024;

  /// Minimum gap between accepted "Refresh all" taps (a UX debounce). The
  /// data.gov.sg limit itself is enforced for every caller by the shared
  /// limiter ([DataGovSgRateLimit]), not by this cooldown.
  static const Duration minEnvironmentRefreshInterval = Duration(seconds: 15);

  /// How often time-relative text is recomputed while the screen is open
  /// ("N min ago", "Out of date", the UV night rule, bus ETAs). A UI-only
  /// rebuild: it never sends a request, so there is still no automatic
  /// polling.
  static const Duration uiTick = Duration(seconds: 15);
}

/// Layout transitions (presentation only; docs/assumptions.md, "Motion").
abstract final class AppMotion {
  /// How long a card takes to grow or shrink to new content. The short end
  /// of the 0.3–0.4 s response of a critically damped UI spring, because a
  /// card resizing is a reveal, not a journey across the screen.
  static const Duration resize = Duration(milliseconds: 250);
}

/// Colour palette (E1; docs/assumptions.md, "Palette persistence").
abstract final class AppearanceConfig {
  /// The longest startup waits for the stored colour palette (E1) before it
  /// shows the default. The read is local, normally a few milliseconds.
  static const Duration paletteLoadTimeout = Duration(milliseconds: 500);
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

  /// The arrivals footer keeps the attribution and "Refresh arrivals" side by
  /// side while it has at least this × the text scale; otherwise the button
  /// goes below the attribution (M5: 2× text overflowed a phone).
  static const double arrivalsFooterMinRowWidth = 280;
}

/// Stale thresholds (§6.3, docs/assumptions.md).
abstract final class StaleAfter {
  static const Duration twoHourForecast = Duration(hours: 3);
  static const Duration pm25 = Duration(hours: 2);
  static const Duration psi = Duration(hours: 2);
  static const Duration uvDaytime = Duration(hours: 2);
}

/// UV is measured roughly 07:00–20:00 SGT. Outside [uvDayStartHour,
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

  /// One encoded polyline per service direction (P2-M2 ride line; loaded
  /// only when the map is opened with a direct-bus journey).
  static final Uri routes = Uri.parse(
    'https://data.busrouter.sg/v1/routes.min.json',
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

  /// A direction listing more stop codes than this is an invalid entry
  /// (#59): the planner and the ride matcher run on the UI isolate, and a
  /// broken or hostile file could otherwise freeze them. Far above the
  /// longest real direction (104 stops, docs/assumptions.md).
  static const int maxStopsPerDirection = 300;

  /// The same for one encoded route line, in characters, checked before it
  /// is decoded. The longest real line has 314 points, about 4,000
  /// characters.
  static const int maxEncodedLineLength = 20000;
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
