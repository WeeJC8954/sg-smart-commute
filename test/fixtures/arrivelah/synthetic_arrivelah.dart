// Hand-made synthetic ArriveLah bodies for the parser, domain and repository
// tests (owner decisions A-4a and A-4c,
// docs/arrivelah-onemap-fixture-licensing-audit.md). They replace captured
// responses whose redistribution rights could not be established. Nothing
// here is copied from ArriveLah, LTA or any other source; only the field names
// and shapes are kept (docs/data-sources.md § ArriveLah). Stop codes, service
// numbers and origin/destination codes start with F (no real one does),
// free text is marked fake, positions are laid out by formula and every time
// is [arriveLahClock] plus an offset on a fake date. README.md here lists the
// cases.
import 'dart:convert';

/// The tests' fixed clock for these bodies: 2001-02-03 12:00:00 +08:00.
final DateTime arriveLahClock = DateTime.utc(2001, 2, 3, 4);

const String busyStopCode = 'F0301';
const String loopStopCode = 'F7500';
const String unknownStopCode = 'F0000';

/// [after] the clock as ArriveLah writes it: Singapore wall time, `+08:00`.
String sgtTime(Duration after) {
  final t = arriveLahClock.add(after).add(const Duration(hours: 8));
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)}T${two(t.hour)}:'
      '${two(t.minute)}:${two(t.second)}+08:00';
}

/// `duration_ms` is computed when the body is made: here 40 s before the
/// clock, so it is deliberately stale and never matches `time`.
const Duration _madeBeforeClock = Duration(seconds: 40);

Map<String, Object?> _bus(
  Duration after, {
  String load = 'SEA',
  String feature = 'WAB',
  String type = 'SD',
  int visit = 1,
  bool monitored = true,
}) {
  // A fake position laid out from the time: 0.0001° per second of [after].
  final step = 0.0001 * after.inSeconds;
  return {
    'time': sgtTime(after),
    'duration_ms': (after + _madeBeforeClock).inMilliseconds,
    // A schedule-based (unmonitored) bus has no position: lat/lng 0.
    'lat': monitored ? 1.25 + step : 0,
    'lng': monitored ? 103.75 + step : 0,
    'load': load,
    'feature': feature,
    'type': type,
    'visit_number': visit,
    'origin_code': 'F8001',
    'destination_code': 'F8002',
    'monitored': monitored ? 1 : 0,
  };
}

/// `subsequent` is the legacy copy of `next2`, as ArriveLah sends it.
Map<String, Object?> _service(
  String no,
  Map<String, Object?>? next, [
  Map<String, Object?>? next2,
  Map<String, Object?>? next3,
]) => {
  'no': no,
  'operator': 'FAKE',
  'next': next,
  'subsequent': next2,
  'next2': next2,
  'next3': next3,
};

Duration _ms(int minutes, [int seconds = 0]) =>
    Duration(minutes: minutes, seconds: seconds);

/// A busy stop, [busyStopCode]: ten services in a provider order that is
/// not sorted.
final String busyStopBody = jsonEncode({
  'services': [
    _service(
      'F10',
      _bus(_ms(1, 5), type: 'DD'),
      _bus(_ms(9, 40), type: 'DD'),
      _bus(_ms(21, 15), type: 'DD'),
    ),
    _service(
      'F100',
      _bus(_ms(2, 30), load: 'SDA'),
      _bus(_ms(12, 10), load: 'LSD', type: 'BD'),
      _bus(_ms(30), type: 'DD'),
    ),
    _service('F2', _bus(_ms(0, 40)), _bus(_ms(14))), // next3: null
    _service('F2A', _bus(_ms(6, 20))), // only next
    _service('F5', _bus(_ms(3, 10)), _bus(_ms(11, 45)), _bus(_ms(25, 5))),
    _service(
      'F7',
      _bus(_ms(4), feature: ''), // not marked accessible
      _bus(_ms(18), monitored: false),
    ),
    // next is 20 s past: still "Arr".
    _service('F8', _bus(-_ms(0, 20)), _bus(_ms(7, 30)), _bus(_ms(16))),
    _service(
      'F9',
      _bus(_ms(5), monitored: false),
      _bus(_ms(20), monitored: false),
      _bus(_ms(35), monitored: false),
    ),
    _service(
      'F11',
      _bus(_ms(8, 15), load: 'LSD', type: 'BD'),
      _bus(_ms(19, 50), load: 'SDA', type: 'DD'),
      _bus(_ms(33, 30)),
    ),
    _service('F12', _bus(_ms(10)), _bus(_ms(22)), _bus(_ms(40))),
  ],
});

/// A loop terminal, [loopStopCode]: `F29` and `F30` start and end their loop
/// here (visit 2 = a bus finishing the loop), and `F31` is listed twice.
final String loopStopBody = jsonEncode({
  'services': [
    _service(
      'F29',
      _bus(_ms(1, 30), visit: 2, type: 'DD'),
      _bus(_ms(3), visit: 2, type: 'DD'),
      _bus(_ms(5), monitored: false, type: 'DD'),
    ),
    _service(
      'F30',
      _bus(_ms(3, 35), visit: 2, load: 'SDA'),
      _bus(_ms(4), monitored: false),
      _bus(_ms(7), visit: 2),
    ),
    _service(
      'F3',
      _bus(_ms(0), monitored: false),
      _bus(_ms(12), monitored: false),
      _bus(_ms(24), monitored: false),
    ),
    _service('F31', _bus(_ms(6)), _bus(_ms(17))),
    _service('F31', _bus(_ms(2)), _bus(_ms(11))),
    _service(
      'F4',
      _bus(_ms(17), monitored: false),
      _bus(_ms(32), monitored: false),
    ),
  ],
});

/// An unknown stop: an empty list, not a failure.
final String emptyStopBody = jsonEncode({'services': []});

/// ArriveLah's failure shape (sent with HTTP 200): `error` and `statusCode`.
final String errorBody = jsonEncode({
  'error': 'Synthetic failure (fake).',
  'statusCode': 500,
});

/// The usage message sent when no `id` is given: an object with no
/// `services`.
final String noIdInstructionBody = jsonEncode({
  'name': 'fake-arrivals',
  'project_url': 'https://example.invalid/fake-arrivals',
  'instruction': 'Synthetic instruction (fake): an id parameter is required.',
});
