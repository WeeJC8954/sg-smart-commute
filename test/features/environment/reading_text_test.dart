import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/features/environment/domain/environment_models.dart';
import 'package:sg_smart_commute/features/environment/presentation/reading_text.dart';

EnvironmentalReading<T> reading<T>(
  T value,
  SpatialScope scope,
  String scopeName,
) => EnvironmentalReading<T>(
  value: value,
  observedAt: DateTime.utc(2026, 10, 1, 4), // 12:00 SGT
  fetchedAt: DateTime.utc(2026, 10, 1, 4, 5),
  source: 'test',
  scope: scope,
  scopeName: scopeName,
  staleAfter: const Duration(hours: 2),
);

void main() {
  final noon = DateTime.utc(2026, 10, 1, 4, 12); // 12:12 SGT
  final night = DateTime.utc(2026, 10, 1, 14); // 22:00 SGT

  test('tile titles keep the spec labels', () {
    expect(ReadingText.psiTitle, '24-hr PSI');
    expect(ReadingText.pm25Title, '1-hr PM2.5');
  });

  test('PSI, PM2.5 and UV split into a value and an official band', () {
    expect(
      ReadingText.psiParts(reading<num>(54, SpatialScope.region, 'central')),
      (value: '54', band: 'Moderate'),
    );
    expect(
      ReadingText.pm25Parts(reading<num>(18, SpatialScope.region, 'central')),
      (value: '18 µg/m³', band: 'Normal'),
    );
    expect(ReadingText.uvParts(7), (value: '7', band: 'High'));
  });

  test('scope labels', () {
    expect(
      ReadingText.scope(reading<num>(1, SpatialScope.region, 'central')),
      'Central region',
    );
    expect(
      ReadingText.scope(reading<String?>('x', SpatialScope.area, 'Bishan')),
      'Bishan area',
    );
    expect(
      ReadingText.scope(reading<int>(1, SpatialScope.national, 'Singapore')),
      'Singapore (national)',
    );
  });

  test('forecast with and without a condition', () {
    expect(
      ReadingText.forecast(reading<String?>('Cloudy', SpatialScope.area, 'A')),
      'Cloudy',
    );
    expect(
      ReadingText.forecast(reading<String?>(null, SpatialScope.area, 'A')),
      'No forecast for this area',
    );
  });

  test('UV by day shows the value and category', () {
    final r = reading<int>(5, SpatialScope.national, 'Singapore');
    expect(ReadingText.uv(r, noon), 'UV 5 (Moderate)');
    expect(ReadingText.uvNightDetail(r, noon), isNull);
  });

  test('UV at night says it is not measured and keeps the last reading', () {
    final r = reading<int>(0, SpatialScope.national, 'Singapore');
    expect(ReadingText.uv(r, night), 'UV not measured at night');
    expect(
      ReadingText.uvNightDetail(r, night),
      'Last reading UV 0 (Low) at 12:00 SGT',
    );
  });

  test('timestamp in SGT with age; future timestamps show "just now"', () {
    expect(
      ReadingText.timestamp(DateTime.utc(2026, 10, 1, 4), noon),
      'As of 12:00 SGT · 12 min ago',
    );
    expect(
      ReadingText.timestamp(DateTime.utc(2026, 10, 1, 5), noon),
      'As of 13:00 SGT · just now',
    );
  });

  test('fractional values keep one decimal', () {
    expect(
      ReadingText.pm25Parts(reading<num>(18.24, SpatialScope.region, 'east')),
      (value: '18.2 µg/m³', band: 'Normal'),
    );
  });

  test('stale readings are marked in plain words', () {
    expect(ReadingText.staleLabel, 'Out of date');
  });
}
