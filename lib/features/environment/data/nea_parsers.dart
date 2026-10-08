/// data.gov.sg v2 real-time payload → domain mapping. Shapes verified against
/// live responses on 2026-10-01 (test/fixtures/, docs/api-feasibility.md).
///
/// Every function throws [InvalidApiResponse] on an unexpected shape and
/// [ApiUnavailable] when the envelope reports an error (`code != 0`).
library;

import '../../../core/errors/app_failure.dart';
import '../../../core/errors/failure_guard.dart';
import '../../../core/geo/geo.dart';
import '../../../core/time/sgt_format.dart';
import '../domain/environment_models.dart';

ForecastSnapshot parseTwoHourForecast(
  Object? json, {
  required DateTime fetchedAt,
}) => guardAppFailureSync(context: 'two-hr-forecast', () {
  final data = _data(json);
  final areas = _list(data['area_metadata']);
  final item = _latest(_list(data['items']), (i) => _time(i['timestamp']));
  final conditions = <String, String>{
    for (final f in _list(item['forecasts']).cast<Map<String, dynamic>>())
      f['area'] as String: f['forecast'] as String,
  };
  // Only the source wording is shown; a missing or odd valid_period loses
  // that line, never the whole tile.
  final valid = item['valid_period'];
  final validText = valid is Map<String, dynamic> ? valid['text'] : null;
  return ForecastSnapshot(
    areas: [
      for (final a in areas.cast<Map<String, dynamic>>())
        ForecastArea(
          name: a['name'] as String,
          location: _latLng(a['label_location']),
          condition: conditions[a['name']],
        ),
    ],
    updatedAt: _time(item['update_timestamp']),
    validText: validText is String ? validText : '',
    fetchedAt: fetchedAt,
  );
});

UvSnapshot parseUv(Object? json, {required DateTime fetchedAt}) =>
    guardAppFailureSync(context: 'uv', () {
      final data = _data(json);
      final record = _latest(
        _list(data['records']),
        (r) => _time(r['timestamp']),
      );
      final latest = _latest(_list(record['index']), (e) => _time(e['hour']));
      return UvSnapshot(
        value: (latest['value'] as num).toInt(),
        observedAt: _time(latest['hour']),
        fetchedAt: fetchedAt,
      );
    });

/// 1-hour PM2.5 (`pm25_one_hourly`), µg/m³.
RegionalSnapshot parsePm25(Object? json, {required DateTime fetchedAt}) =>
    _regional(json, 'pm25_one_hourly', AirMetric.pm25OneHour, fetchedAt);

/// 24-hour PSI (`psi_twenty_four_hourly`). Never any other PSI-payload field.
RegionalSnapshot parsePsi(Object? json, {required DateTime fetchedAt}) =>
    _regional(
      json,
      'psi_twenty_four_hourly',
      AirMetric.psiTwentyFourHour,
      fetchedAt,
    );

RegionalSnapshot _regional(
  Object? json,
  String field,
  AirMetric metric,
  DateTime fetchedAt,
) => guardAppFailureSync(context: field, () {
  final data = _data(json);
  final regions = <String, LatLng>{
    for (final r in _list(data['regionMetadata']).cast<Map<String, dynamic>>())
      if (r['name'] != 'national')
        r['name'] as String: _latLng(r['labelLocation']),
  };
  final item = _latest(_list(data['items']), (i) => _time(i['timestamp']));
  final readings = (item['readings'] as Map<String, dynamic>)[field];
  if (readings is! Map<String, dynamic>) {
    throw InvalidApiResponse('missing $field');
  }
  final values = <String, num>{
    for (final e in readings.entries)
      if (regions.containsKey(e.key)) e.key: _finite(e.value),
  };
  if (regions.isEmpty || values.isEmpty) {
    throw InvalidApiResponse('no regions for $field');
  }
  return RegionalSnapshot(
    metric: metric,
    regions: regions,
    values: values,
    observedAt: _time(item['timestamp']),
    fetchedAt: fetchedAt,
  );
});

// --- helpers --------------------------------------------------------------

Map<String, dynamic> _data(Object? json) {
  if (json is! Map<String, dynamic>) {
    throw const InvalidApiResponse('not an object');
  }
  final code = json['code'];
  if (code is num && code != 0) {
    throw ApiUnavailable('code $code: ${json['errorMsg']}');
  }
  final data = json['data'];
  if (data is! Map<String, dynamic>) {
    throw const InvalidApiResponse('missing data');
  }
  return data;
}

List<dynamic> _list(Object? value) {
  if (value is! List) throw const InvalidApiResponse('expected a list');
  return value;
}

Map<String, dynamic> _latest(
  List<dynamic> items,
  DateTime Function(Map<String, dynamic>) at,
) {
  if (items.isEmpty) throw const InvalidApiResponse('empty list');
  final maps = items.cast<Map<String, dynamic>>();
  return maps.reduce((a, b) => at(b).isAfter(at(a)) ? b : a);
}

DateTime _time(Object? value) => parseSourceTimestamp(value as String);

LatLng _latLng(Object? value) {
  final m = value as Map<String, dynamic>;
  return LatLng(
    _finite(m['latitude']).toDouble(),
    _finite(m['longitude']).toDouble(),
  );
}

/// A JSON number; a literal beyond double range (`1e400`) decodes to infinity,
/// which would break the display and the nearest-region search later (#55).
num _finite(Object? value) => value is num && value.isFinite
    ? value
    : throw InvalidApiResponse('not a finite number: $value');
