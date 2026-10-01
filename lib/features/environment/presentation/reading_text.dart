import '../../../core/time/sgt_format.dart';
import '../domain/bands.dart';
import '../domain/environment_models.dart';

/// Display strings for dashboard readings (§6.1, §7). Pure, so the exact
/// wording — especially "24-hr PSI" vs "1-hr PM2.5" — is unit-tested.
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

  static String pm25(EnvironmentalReading<num> r) {
    final band = pm25Band(r.value);
    final n = _number(r.value);
    return band == null ? '$pm25Title $n µg/m³' : '$pm25Title $n µg/m³ ($band)';
  }

  static String psi(EnvironmentalReading<num> r) {
    final band = psiBand(r.value);
    final n = _number(r.value);
    return band == null ? '$psiTitle $n' : '$psiTitle $n ($band)';
  }

  /// "As of 20:00 SGT · 12 min ago".
  static String timestamp(DateTime observedAt, DateTime now) =>
      'As of ${formatSgtTime(observedAt)} SGT · ${formatAge(observedAt, now)}';

  static String _number(num v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
}
