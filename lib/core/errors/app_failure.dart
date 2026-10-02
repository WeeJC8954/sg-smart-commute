/// Typed failures carried in `AsyncValue.error` (guide v2.1 §13).
///
/// Only the failures Milestones 1–3 can produce are defined here. The rest of
/// the §13 list (bus arrival) arrives with that feature. An empty
/// place search is an empty result list, not a failure.
sealed class AppFailure implements Exception {
  const AppFailure();

  /// Friendly, user-facing message. No technical detail.
  String get message;

  @override
  String toString() => '$runtimeType: $message';
}

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

final class ApiRateLimited extends AppFailure {
  const ApiRateLimited({this.retryAfter});
  final Duration? retryAfter;
  @override
  String get message => 'The data service is busy. Please retry in a moment.';
}

final class ApiUnauthorized extends AppFailure {
  const ApiUnauthorized();
  @override
  String get message => 'The data service refused the request.';
}

final class ApiUnavailable extends AppFailure {
  const ApiUnavailable([this.detail]);
  final String? detail;
  @override
  String get message => 'The data service is unavailable right now.';
}

final class InvalidApiResponse extends AppFailure {
  const InvalidApiResponse([this.detail]);
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

  /// Which dataset failed, e.g. "busrouter" or "MRT stations".
  final String dataset;
  final String? detail;
  @override
  String get message => dataset == 'MRT stations'
      ? 'MRT station data is unavailable.'
      : 'Bus data is unavailable right now.';
}
