/// Typed failures carried in `AsyncValue.error` (guide v2.1 §13).
///
/// Only the failures Milestones 1–4 can produce are defined here. An empty
/// place search is an empty result list, not a failure.
sealed class AppFailure implements Exception {
  const AppFailure();

  /// Friendly, user-facing message. No technical detail.
  String get message;

  /// Technical detail for developers (e.g. which field a parser rejected).
  /// Never shown to the user; logged in debug builds by `guardAppFailure`.
  String? get detail => null;

  @override
  String toString() {
    final d = detail;
    return d == null ? '$runtimeType: $message' : '$runtimeType: $message ($d)';
  }
}

/// The user-facing message for an error caught from a provider or a call.
/// Errors are [AppFailure]s by contract (§13); anything else is reported as
/// an unexpected response, never with technical detail.
String failureMessage(Object? error) =>
    error is AppFailure ? error.message : const InvalidApiResponse().message;

// --- Location -------------------------------------------------------------

sealed class LocationFailure extends AppFailure {
  const LocationFailure();
}

final class LocationPermissionDenied extends LocationFailure {
  const LocationPermissionDenied();
  @override
  String get message => 'Location permission was not granted.';
}

final class LocationPermissionPermanentlyDenied extends LocationFailure {
  const LocationPermissionPermanentlyDenied();
  @override
  String get message =>
      'Location permission is blocked. You can allow it in settings.';
}

/// The permission prompt was not answered within the permission timeout
/// (e.g. a browser prompt left open). The attempt carries on: if the prompt is
/// answered later, its fix follows the late-fix rule.
final class LocationPermissionUnanswered extends LocationFailure {
  const LocationPermissionUnanswered();
  @override
  String get message => 'The location request has not been answered yet.';
}

final class LocationServiceDisabled extends LocationFailure {
  const LocationServiceDisabled();
  @override
  String get message => 'Location services are turned off.';
}

final class LocationTimeout extends LocationFailure {
  const LocationTimeout();
  @override
  String get message => 'Finding your location took too long.';
}

final class LocationOutsideSingapore extends LocationFailure {
  const LocationOutsideSingapore();
  @override
  String get message => 'Your reported location is outside Singapore.';
}

/// Any other acquisition error (not in the §13 list; see docs/assumptions.md).
final class LocationUnavailable extends LocationFailure {
  const LocationUnavailable();
  @override
  String get message => 'Your location is unavailable right now.';
}

// --- Network / API --------------------------------------------------------

final class NetworkUnavailable extends AppFailure {
  const NetworkUnavailable();
  @override
  String get message => 'Network unavailable. Check your connection and retry.';
}

/// HTTP 429. [retryAfter] is how long the server asked us to wait (from
/// `Retry-After`, capped); `JsonHttpClient` sends nothing more to that host
/// until it has passed.
final class ApiRateLimited extends AppFailure {
  const ApiRateLimited({this.retryAfter});
  final Duration? retryAfter;
  @override
  String get message {
    final wait = retryAfter;
    if (wait == null || wait <= Duration.zero) {
      return 'The data service is busy. Please retry in a moment.';
    }
    return 'The data service is busy. Please retry in ${_waitText(wait)}.';
  }
}

/// "1 second", "45 seconds", "3 minutes": rounded up, never "0".
String _waitText(Duration wait) {
  final seconds = (wait.inMilliseconds / 1000).ceil();
  if (seconds < 120) return seconds == 1 ? '1 second' : '$seconds seconds';
  return '${(seconds / 60).ceil()} minutes';
}

final class ApiUnauthorized extends AppFailure {
  const ApiUnauthorized();
  @override
  String get message => 'The data service refused the request.';
}

final class ApiUnavailable extends AppFailure {
  const ApiUnavailable([this.detail]);
  @override
  final String? detail;
  @override
  String get message => 'The data service is unavailable right now.';
}

final class InvalidApiResponse extends AppFailure {
  const InvalidApiResponse([this.detail]);
  @override
  final String? detail;
  @override
  String get message => 'The data service returned something unexpected.';
}

// --- Place search ---------------------------------------------------------

/// A 6-digit postal-code query returned results, but none with exactly that
/// postcode (§8.2, §8.3). Fuzzy near-misses are never offered as the match.
final class NoExactPostalMatch extends AppFailure {
  const NoExactPostalMatch(this.postalCode);
  final String postalCode;
  @override
  String get message => 'No exact match for $postalCode.';
}

// --- Journey ----------------------------------------------------------------

/// Static transport data (busrouter stops/services or the bundled MRT asset)
/// could not be loaded or did not match the expected schema (§13).
final class StaticDataUnavailable extends AppFailure {
  const StaticDataUnavailable(this.dataset, [this.detail]);

  /// Which dataset failed.
  final StaticDataset dataset;
  @override
  final String? detail;
  @override
  String get message => switch (dataset) {
    StaticDataset.busRoutes => 'Bus data is unavailable right now.',
    StaticDataset.mrtStations => 'MRT station data is unavailable.',
    StaticDataset.busRouteGeometry =>
      'The bus route line is unavailable right now.',
  };
}

/// The static transport datasets [StaticDataUnavailable] can be about.
enum StaticDataset {
  /// busrouter stops and services.
  busRoutes,

  /// The bundled MRT station asset.
  mrtStations,

  /// busrouter route lines (the map).
  busRouteGeometry,
}

// --- Bus arrival ------------------------------------------------------------

/// The live-arrival provider answered with an error instead of arrivals
/// (ArriveLah reports upstream failures as HTTP 200 with an `error` field).
final class BusArrivalUnavailable extends AppFailure {
  const BusArrivalUnavailable([this.detail]);
  @override
  final String? detail;
  @override
  String get message => 'Live arrival times are unavailable right now.';
}
