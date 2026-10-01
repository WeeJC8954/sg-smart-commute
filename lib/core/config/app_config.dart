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
