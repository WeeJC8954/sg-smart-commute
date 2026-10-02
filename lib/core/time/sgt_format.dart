/// Singapore time helpers (guide §6.3). Singapore is UTC+08:00 with no DST, so
/// a fixed offset is exact and the `timezone` package isn't needed.
library;

const Duration sgtOffset = Duration(hours: 8);

/// `YYYY-MM-DDTHH:MM[:SS[.fff]]` followed by an explicit offset: `Z` or
/// `±HH:MM` (`±HHMM` also accepted).
final RegExp _isoWithOffset = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2})(?:\.\d{1,9})?)?'
  r'(?:Z|([+-])(\d{2}):?(\d{2}))$',
);

/// Parses a source timestamp (ISO-8601 with an explicit offset, e.g.
/// `2026-10-01T20:00:00+08:00` or `2026-10-01T12:00:00Z`) and returns it in
/// UTC. Used for every provider timestamp (NEA, ArriveLah).
///
/// Strict on purpose. `DateTime.parse` alone rolls out-of-range fields over
/// (`2026-13-45T25:00:00+08:00` becomes a valid instant in 2027) and reads a
/// value without an offset as device-local time; either way it would invent a
/// time. So the value must match the pattern above, have an offset of less
/// than 24 h with minutes below 60, and the parsed instant must give back
/// exactly the date and time fields that were sent. Throws [FormatException]
/// otherwise.
DateTime parseSourceTimestamp(String value) {
  final m = _isoWithOffset.firstMatch(value);
  if (m == null) {
    throw FormatException('not an ISO-8601 time with an offset', value);
  }
  var offset = Duration.zero;
  if (m[7] != null) {
    final hours = int.parse(m[8]!);
    final minutes = int.parse(m[9]!);
    if (hours > 23 || minutes > 59) {
      throw FormatException('invalid offset', value);
    }
    offset = Duration(hours: hours, minutes: minutes) * (m[7] == '-' ? -1 : 1);
  }
  final instant = DateTime.parse(value).toUtc();
  final wall = instant.add(offset); // the wall-clock time that was sent
  final sent = [for (var i = 1; i <= 6; i++) int.parse(m[i] ?? '0')];
  final got = [
    wall.year,
    wall.month,
    wall.day,
    wall.hour,
    wall.minute,
    wall.second,
  ];
  for (var i = 0; i < sent.length; i++) {
    if (sent[i] != got[i]) {
      throw FormatException('date or time field out of range', value);
    }
  }
  return instant;
}

DateTime _toSgtWallClock(DateTime instant) => instant.toUtc().add(sgtOffset);

String _two(int n) => n.toString().padLeft(2, '0');

/// `HH:mm` in Singapore time.
String formatSgtTime(DateTime instant) {
  final t = _toSgtWallClock(instant);
  return '${_two(t.hour)}:${_two(t.minute)}';
}

/// Hour of day (0–23) in Singapore time.
int sgtHour(DateTime instant) => _toSgtWallClock(instant).hour;

/// "just now" / "N min ago" / "N h ago". A negative age (device clock behind
/// the source) is shown as "just now"; a negative age is never displayed.
String formatAge(DateTime observedAt, DateTime now) {
  final age = now.difference(observedAt);
  if (age.inMinutes < 1) return 'just now';
  if (age.inMinutes < 60) return '${age.inMinutes} min ago';
  return '${age.inHours} h ago';
}
