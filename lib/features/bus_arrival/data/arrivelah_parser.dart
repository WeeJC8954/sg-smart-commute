import '../../../core/errors/app_failure.dart';
import '../../../core/time/sgt_format.dart';
import '../domain/bus_arrival.dart';

const String arriveLahSource = 'ArriveLah';

/// The slots read per service. `subsequent` is skipped: ArriveLah sends it as
/// a legacy copy of `next2`.
const List<String> _slots = ['next', 'next2', 'next3'];

/// `YYYY-MM-DDTHH:MM:SS[.fff]` plus an explicit offset (`+08:00` or `Z`).
/// Without an offset, `DateTime.parse` would read it as device-local time.
final RegExp _isoWithOffset = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?'
  r'(Z|([+-])(\d{2}):(\d{2}))$',
);

/// Parses an ArriveLah stop response (observed 2026-10-02, docs/
/// data-sources.md): `{"services": [{"no", "operator", "next", "subsequent",
/// "next2", "next3"}]}`, where each slot is null or
/// `{"time", "duration_ms", "load", "feature", "type", "visit_number",
/// "monitored", …}`.
///
/// - `{"error": …}` (sent with HTTP 200 when LTA fails) → [BusArrivalUnavailable].
/// - Anything without a `services` list → [InvalidApiResponse].
/// - A malformed service entry is skipped. If every entry is malformed, the
///   schema has changed → [InvalidApiResponse].
/// - A slot's time is parsed with its own offset and stored in UTC. A missing
///   or invalid time gives `estimatedArrival: null`; nothing is fabricated.
/// - `load`, `feature`, `type`, `monitored`, `visit_number` are optional: an
///   unknown value becomes null and never fails the arrival.
/// - `duration_ms` is ignored: it was computed when the response was made and
///   goes stale in caches. The ETA comes from `time` and the app clock.
StopArrivals parseArriveLah(Object? json, String busStopCode) {
  if (json is! Map<String, dynamic>) {
    throw const InvalidApiResponse('ArriveLah: not an object');
  }
  final error = json['error'];
  if (error != null) {
    throw BusArrivalUnavailable('ArriveLah: $error');
  }
  final services = json['services'];
  if (services is! List) {
    throw const InvalidApiResponse('ArriveLah: no services list');
  }
  final parsed = <ServiceArrivals>[];
  for (final entry in services) {
    final service = _service(entry, busStopCode);
    if (service != null) parsed.add(service);
  }
  if (services.isNotEmpty && parsed.isEmpty) {
    throw const InvalidApiResponse('ArriveLah: no valid service entries');
  }
  return StopArrivals(busStopCode: busStopCode, services: parsed);
}

ServiceArrivals? _service(Object? entry, String busStopCode) {
  if (entry is! Map<String, dynamic>) return null;
  final no = entry['no'];
  if (no is! String || no.trim().isEmpty) return null;
  final serviceNo = no.trim();
  return ServiceArrivals(
    serviceNo: serviceNo,
    arrivals: [
      for (final slot in _slots)
        if (entry[slot] case final Map<String, dynamic> bus)
          BusArrival(
            serviceNo: serviceNo,
            busStopCode: busStopCode,
            estimatedArrival: _time(bus['time']),
            load: _load(bus['load']),
            wheelchairAccessible: _wheelchair(bus['feature']),
            type: _type(bus['type']),
            monitored: _monitored(bus['monitored']),
            visitNumber: _int(bus['visit_number']),
            source: arriveLahSource,
          ),
    ],
  );
}

/// The instant in UTC, or null if [value] is not a valid ISO time with an
/// offset. `DateTime.parse` alone is not enough: it rolls out-of-range fields
/// over (month 13, hour 25 …) into a different, made-up instant, so the
/// parsed result must give back exactly the fields that were sent.
DateTime? _time(Object? value) {
  if (value is! String) return null;
  final text = value.trim();
  final m = _isoWithOffset.firstMatch(text);
  if (m == null) return null;
  final DateTime instant;
  try {
    instant = parseSourceTimestamp(text);
  } on FormatException {
    return null;
  }
  final offset = m[7] == 'Z'
      ? Duration.zero
      : Duration(hours: int.parse(m[9]!), minutes: int.parse(m[10]!)) *
            (m[8] == '-' ? -1 : 1);
  if (offset.abs() >= const Duration(hours: 24)) return null;
  final wall = instant.add(offset); // the wall-clock time that was sent
  final sent = [for (var i = 1; i <= 6; i++) int.parse(m[i]!)];
  final got = [
    wall.year,
    wall.month,
    wall.day,
    wall.hour,
    wall.minute,
    wall.second,
  ];
  for (var i = 0; i < 6; i++) {
    if (sent[i] != got[i]) return null;
  }
  return instant;
}

BusLoad? _load(Object? value) => switch (value) {
  'SEA' => BusLoad.seatsAvailable,
  'SDA' => BusLoad.standingAvailable,
  'LSD' => BusLoad.limitedStanding,
  _ => null,
};

/// LTA: `WAB` = wheelchair-accessible bus, empty = not marked accessible.
bool? _wheelchair(Object? value) => switch (value) {
  'WAB' => true,
  '' => false,
  _ => null,
};

BusType? _type(Object? value) => switch (value) {
  'SD' => BusType.singleDeck,
  'DD' => BusType.doubleDeck,
  'BD' => BusType.bendy,
  _ => null,
};

bool? _monitored(Object? value) => switch (value) {
  1 || '1' || true => true,
  0 || '0' || false => false,
  _ => null,
};

int? _int(Object? value) => switch (value) {
  final int n => n,
  final String s => int.tryParse(s),
  _ => null,
};
