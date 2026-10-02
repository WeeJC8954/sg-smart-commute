import '../../../core/time/sgt_format.dart';
import '../domain/bands.dart';
import '../domain/environment_models.dart';

/// A reading split for display: [value] large, [band] as a text pill.
typedef ReadingParts = ({String value, String? band});

/// Display strings for dashboard readings (§6.1, §7). Pure, so the exact
/// wording — especially the "24-hr PSI" / "1-hr PM2.5" titles — is
/// unit-tested.
abstract final class ReadingText {
  static const String forecastTitle = '2-hr forecast';
  static const String uvTitle = 'UV index';
  static const String pm25Title = '1-hr PM2.5';
  static const String psiTitle = '24-hr PSI';

  static String regionName(String region) => region.isEmpty
      ? region
      : '${region[0].toUpperCase()}${region.substring(1)}';

  static String scope(EnvironmentalReading<Object?> r) => switch (r.scope) {
    SpatialScope.national => '${r.scopeName} (national)',
    SpatialScope.region => '${regionName(r.scopeName)} region',
    SpatialScope.area => '${r.scopeName} area',
    SpatialScope.station => '${r.scopeName} station',
  };

  static String forecast(EnvironmentalReading<String?> r) =>
      r.value ?? 'No forecast for this area';

  static String uvValue(int value) {
    final band = uvBand(value);
    return band == null ? 'UV $value' : 'UV $value ($band)';
  }

  /// UV headline. At night the last reading is still shown, with its time,
  /// and is not treated as an error (§6.1).
  static String uv(EnvironmentalReading<int> r, DateTime now) =>
      isUvNight(now) ? 'UV not measured at night' : uvValue(r.value);

  static String? uvNightDetail(EnvironmentalReading<int> r, DateTime now) =>
      isUvNight(now)
      ? 'Last reading ${uvValue(r.value)} at ${formatSgtTime(r.observedAt)} SGT'
      : null;

  /// Shown for a reading older than its dataset's threshold (§6.3).
  static const String staleLabel = 'Out of date';

  /// The number shown large on a tile, and its official band (null when no
  /// NEA band applies). The metric label is the tile title, shown once.
  static ReadingParts pm25Parts(EnvironmentalReading<num> r) =>
      (value: '${_number(r.value)} µg/m³', band: pm25Band(r.value));

  static ReadingParts psiParts(EnvironmentalReading<num> r) =>
      (value: _number(r.value), band: psiBand(r.value));

  static ReadingParts uvParts(int value) =>
      (value: '$value', band: uvBand(value));

  /// "As of 20:00 SGT · 12 min ago".
  static String timestamp(DateTime observedAt, DateTime now) =>
      'As of ${formatSgtTime(observedAt)} SGT · ${formatAge(observedAt, now)}';

  static String _number(num v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
}
