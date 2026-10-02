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

    test('valid ISO times with an offset keep their meaning', () {
      expect(
        parseSourceTimestamp('2026-10-01T20:06:33+08:00'),
        DateTime.utc(2026, 10, 1, 12, 6, 33),
      );
      expect(
        parseSourceTimestamp('2026-10-01T12:00:00Z'),
        DateTime.utc(2026, 10, 1, 12),
      );
      expect(
        parseSourceTimestamp('2026-10-01T23:30:00-05:30'),
        DateTime.utc(2026, 10, 2, 5),
      );
      expect(
        parseSourceTimestamp('2026-10-02T00:15:00+08:00'), // SGT after midnight
        DateTime.utc(2026, 10, 1, 16, 15),
      );
      expect(
        parseSourceTimestamp('2026-10-01T20:00:00.250+08:00'),
        DateTime.utc(2026, 10, 1, 12, 0, 0, 250),
      );
      expect(
        parseSourceTimestamp('2026-10-01T20:00+08:00'), // no seconds
        DateTime.utc(2026, 10, 1, 12),
      );
      expect(
        parseSourceTimestamp('2026-10-01T20:00:00+0800'),
        DateTime.utc(2026, 10, 1, 12),
      );
      expect(
        parseSourceTimestamp('2028-02-29T08:00:00+08:00'), // leap day
        DateTime.utc(2028, 2, 29),
      );
    });

    group('rejects malformed values instead of rolling them over', () {
      for (final (value, why) in [
        ('2026-13-01T20:00:00+08:00', 'month 13'),
        ('2026-00-10T20:00:00+08:00', 'month 0'),
        ('2026-10-45T20:00:00+08:00', 'day 45'),
        ('2026-02-29T20:00:00+08:00', 'Feb 29 in a non-leap year'),
        ('2026-04-31T20:00:00+08:00', 'April 31'),
        ('2026-10-01T24:00:00+08:00', 'hour 24'),
        ('2026-10-01T25:00:00+08:00', 'hour 25'),
        ('2026-10-01T20:60:00+08:00', 'minute 60'),
        ('2026-10-01T20:00:60+08:00', 'second 60'),
        ('2026-13-45T25:00:00+08:00', 'several fields at once'),
      ]) {
        test('$why: $value', () {
          expect(() => parseSourceTimestamp(value), throwsFormatException);
        });
      }
    });

    group('rejects missing or invalid offsets', () {
      for (final (value, why) in [
        ('2026-10-01T20:00:00', 'no offset (would be device-local)'),
        ('2026-10-01T20:00:00+25:00', 'offset hours 25'),
        ('2026-10-01T20:00:00+08:60', 'offset minutes 60'),
        ('2026-10-01T20:00:00+8:00', 'one-digit offset hour'),
        ('2026-10-01T20:00:00 +08:00', 'space before the offset'),
      ]) {
        test('$why: $value', () {
          expect(() => parseSourceTimestamp(value), throwsFormatException);
        });
      }
    });

    group('rejects other shapes', () {
      for (final value in [
        '',
        '2026-10-01',
        '2026-10-01 20:00:00+08:00',
        '20:00:00+08:00',
        '2026-10-01T20:00:00+08:00 trailing',
        ' 2026-10-01T20:00:00+08:00',
        '1790910067',
      ]) {
        test('"$value"', () {
          expect(() => parseSourceTimestamp(value), throwsFormatException);
        });
      }
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
