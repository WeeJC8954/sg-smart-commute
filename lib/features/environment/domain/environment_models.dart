import '../../../core/config/app_config.dart';
import '../../../core/geo/geo.dart';
import '../../../core/time/sgt_format.dart';

/// Spatial scope of a reading (§6.2). `station` is reserved for later use.
enum SpatialScope { national, region, area, station }

/// One reading for the user's position, with its scope and freshness (§6.2).
class EnvironmentalReading<T> {
  const EnvironmentalReading({
    required this.value,
    required this.observedAt,
    required this.fetchedAt,
    required this.source,
    required this.scope,
    required this.scopeName,
    required this.staleAfter,
    this.daytimeOnly = false,
  });

  final T value;

  /// From the source, UTC.
  final DateTime observedAt;

  /// Device time of the fetch, UTC.
  final DateTime fetchedAt;
  final String source;
  final SpatialScope scope;

  /// e.g. "Bishan", "central", "Singapore".
  final String scopeName;
  final Duration staleAfter;

  /// UV: readings stop overnight, so an old reading at night isn't stale.
  final bool daytimeOnly;

  bool isStale(DateTime nowUtc) {
    if (daytimeOnly && isUvNight(nowUtc)) return false;
    return nowUtc.difference(observedAt) > staleAfter;
  }
}

/// True outside the hours UV is measured (SGT).
bool isUvNight(DateTime nowUtc) {
  final h = sgtHour(nowUtc);
  return h < UvHours.uvDayStartHour || h >= UvHours.uvDayEndHour;
}

// --- Nationwide snapshots (one per dataset, fetched once, located later) ---

class ForecastArea {
  const ForecastArea({
    required this.name,
    required this.location,
    required this.condition,
  });

  final String name;
  final LatLng location;

  /// Null when the payload has no forecast for this area.
  final String? condition;
}

class ForecastSnapshot {
  const ForecastSnapshot({
    required this.areas,
    required this.updatedAt,
    required this.validFrom,
    required this.validTo,
    required this.validText,
    required this.fetchedAt,
  });

  final List<ForecastArea> areas;
  final DateTime updatedAt;
  final DateTime validFrom;
  final DateTime validTo;

  /// Source wording, e.g. "8.00 pm to 10.00 pm".
  final String validText;
  final DateTime fetchedAt;
}

class UvSnapshot {
  const UvSnapshot({
    required this.value,
    required this.observedAt,
    required this.updatedAt,
    required this.fetchedAt,
  });

  /// Latest hourly UV index (national).
  final int value;

  /// The hour of that reading.
  final DateTime observedAt;
  final DateTime updatedAt;
  final DateTime fetchedAt;
}

/// The two regional air metrics. Separate on purpose: never substituted,
/// combined or shown under the same label (§6.1).
enum AirMetric { pm25OneHour, psiTwentyFourHour }

class RegionalSnapshot {
  const RegionalSnapshot({
    required this.metric,
    required this.regions,
    required this.values,
    required this.observedAt,
    required this.updatedAt,
    required this.fetchedAt,
  });

  final AirMetric metric;

  /// Region name → label location. Never contains "national".
  final Map<String, LatLng> regions;

  /// Region name → reading for [metric].
  final Map<String, num> values;
  final DateTime observedAt;
  final DateTime updatedAt;
  final DateTime fetchedAt;
}
