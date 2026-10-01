/// Singapore time helpers (guide §6.3). Singapore is UTC+08:00 with no DST, so
/// a fixed offset is exact and the `timezone` package isn't needed.
library;

const Duration sgtOffset = Duration(hours: 8);

/// Parses an ISO-8601 source timestamp (e.g. `2026-10-01T20:00:00+08:00`)
/// and returns it in UTC. Throws [FormatException] if invalid.
DateTime parseSourceTimestamp(String value) => DateTime.parse(value).toUtc();

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
