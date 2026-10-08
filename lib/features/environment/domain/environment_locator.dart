import '../../../core/config/app_config.dart';
import '../../../core/geo/geo.dart';
import 'environment_models.dart';

/// Pure scope selection (§6.1–§6.2): picks the reading that applies to a
/// position from a nationwide snapshot. Independent of UI and HTTP.
abstract final class EnvironmentLocator {
  /// Nearest forecast area by label location. Value is null if that area has
  /// no forecast in the payload.
  static EnvironmentalReading<String?> forecast(
    ForecastSnapshot s,
    LatLng position,
  ) {
    // The parser rejects a payload without areas.
    assert(s.areas.isNotEmpty, 'no forecast areas');
    final area = _nearest(s.areas, (a) => a.location, position);
    return EnvironmentalReading(
      value: area.condition,
      observedAt: s.updatedAt,
      fetchedAt: s.fetchedAt,
      source: neaSourceLabel,
      scope: SpatialScope.area,
      scopeName: area.name,
      staleAfter: StaleAfter.twoHourForecast,
    );
  }

  /// Nearest region (north/south/east/west/central) for PM2.5 or PSI.
  static EnvironmentalReading<num> regional(
    RegionalSnapshot s,
    LatLng position,
  ) {
    final candidates = s.regions.entries
        .where((e) => s.values.containsKey(e.key))
        .toList();
    // The parser rejects a payload without a reading for a known region.
    assert(candidates.isNotEmpty, 'no regional readings');
    final region = _nearest(candidates, (e) => e.value, position).key;
    return EnvironmentalReading(
      value: s.values[region]!,
      observedAt: s.observedAt,
      fetchedAt: s.fetchedAt,
      source: neaSourceLabel,
      scope: SpatialScope.region,
      scopeName: region,
      staleAfter: switch (s.metric) {
        AirMetric.pm25OneHour => StaleAfter.pm25,
        AirMetric.psiTwentyFourHour => StaleAfter.psi,
      },
    );
  }

  /// UV is a single national value; no position needed.
  static EnvironmentalReading<int> uv(UvSnapshot s) => EnvironmentalReading(
    value: s.value,
    observedAt: s.observedAt,
    fetchedAt: s.fetchedAt,
    source: neaSourceLabel,
    scope: SpatialScope.national,
    scopeName: 'Singapore',
    staleAfter: StaleAfter.uvDaytime,
    daytimeOnly: true,
  );

  static T _nearest<T>(Iterable<T> items, LatLng Function(T) at, LatLng p) {
    T? best;
    var bestDistance = double.infinity;
    for (final item in items) {
      final d = haversineMeters(at(item), p);
      if (d < bestDistance) {
        bestDistance = d;
        best = item;
      }
    }
    return best as T;
  }
}
