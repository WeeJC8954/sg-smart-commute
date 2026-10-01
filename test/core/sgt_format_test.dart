import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/core/time/sgt_format.dart';

void main() {
  group('parseSourceTimestamp', () {
    test('parses +08:00 and stores UTC', () {
      final t = parseSourceTimestamp('2026-10-01T20:00:00+08:00');
      expect(t.isUtc, isTrue);
      expect(t, DateTime.utc(2026, 10, 1, 12));
    });

    test('throws FormatException on garbage', () {
      expect(() => parseSourceTimestamp('not a date'), throwsFormatException);
    });
  });

  group('formatSgtTime', () {
    test('formats a UTC instant at a fixed +08:00 offset', () {
      expect(formatSgtTime(DateTime.utc(2026, 10, 1, 12, 5)), '20:05');
      // Crosses midnight in SGT.
      expect(formatSgtTime(DateTime.utc(2026, 10, 1, 16, 30)), '00:30');
    });
  });

  group('formatAge', () {
    final now = DateTime.utc(2026, 10, 1, 12);

    test('under a minute is "just now"', () {
      expect(
        formatAge(now.subtract(const Duration(seconds: 59)), now),
        'just now',
      );
    });

    test('negative age (device clock behind source) is "just now"', () {
      expect(formatAge(now.add(const Duration(minutes: 5)), now), 'just now');
    });

    test('minutes', () {
      expect(
        formatAge(now.subtract(const Duration(minutes: 1)), now),
        '1 min ago',
      );
      expect(
        formatAge(now.subtract(const Duration(minutes: 59)), now),
        '59 min ago',
      );
    });

    test('hours', () {
      expect(
        formatAge(now.subtract(const Duration(minutes: 60)), now),
        '1 h ago',
      );
      expect(
        formatAge(now.subtract(const Duration(hours: 5, minutes: 40)), now),
        '5 h ago',
      );
    });
  });

  group('sgtHour', () {
    test('returns the hour in Singapore time', () {
      expect(sgtHour(DateTime.utc(2026, 10, 1, 23)), 7);
      expect(sgtHour(DateTime.utc(2026, 10, 1, 12)), 20);
    });
  });
}
