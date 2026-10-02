import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/core/config/app_config.dart';
import 'package:sg_smart_commute/features/places/domain/place_query.dart';

String norm(String raw) => PlaceQuery.normalise(raw).text;

void main() {
  group('normalisation', () {
    test('trims and collapses whitespace', () {
      expect(norm('  Orchard    Road  '), 'Orchard Road');
      expect(norm('Ang\tMo  Kio\nAve 6'), 'Ang Mo Kio Ave 6');
    });

    test('strips a leading Blk / Block before a block number and street', () {
      expect(norm('Blk 123 Ang Mo Kio Ave 6'), '123 Ang Mo Kio Ave 6');
      expect(norm('blk 123 Ang Mo Kio Ave 6'), '123 Ang Mo Kio Ave 6');
      expect(norm('BLK. 201 Tampines St 21'), '201 Tampines St 21');
      expect(norm('Block 345 Yishun Avenue 11'), '345 Yishun Avenue 11');
      expect(norm('Blk 12A Toa Payoh Lor 1'), '12A Toa Payoh Lor 1');
      expect(norm('Blk123 Ang Mo Kio Ave 6'), '123 Ang Mo Kio Ave 6');
    });

    test('cuts a query longer than maxQueryLength (e.g. pasted)', () {
      final long = 'Orchard Road ' * 40; // 520 characters
      final q = norm(long);
      expect(q.length, lessThanOrEqualTo(PlaceSearchConfig.maxQueryLength));
      expect(q, startsWith('Orchard Road Orchard Road'));
      expect(q, isNot(endsWith(' ')));
      expect(norm('a' * 100), 'a' * 100); // at the limit: unchanged
    });

    test('cutting never splits a character', () {
      final emoji = '😀' * 150;
      final q = PlaceQuery.normalise(emoji, maxLength: 3).text;
      expect(q, '😀😀😀');
    });

    test('keeps Blk / Block when it is not a block-number prefix', () {
      expect(norm('Block 71'), 'Block 71'); // a place name
      expect(norm('Blk 123'), 'Blk 123'); // no street: kept as typed
      expect(norm('Blockhouse Bay'), 'Blockhouse Bay');
      expect(norm('Black Box Blk 5 Road'), 'Black Box Blk 5 Road');
    });
  });

  group('postal codes', () {
    test('exactly 6 digits, leading zero allowed, kept as a string', () {
      final q = PlaceQuery.normalise(' 098585 ');
      expect(q.text, '098585');
      expect(q.isPostalCode, isTrue);
      expect(isPostalCode('098585'), isTrue);
      expect(isPostalCode('238801'), isTrue);
    });

    test('5 or 7 digits, spaces inside or non-digits are not postal codes', () {
      for (final s in ['98585', '0985851', '098 585', '09858A', '']) {
        expect(isPostalCode(s), isFalse, reason: s);
      }
    });
  });

  group('minimum length (3, or a postal code)', () {
    test('short queries are not searchable', () {
      expect(PlaceQuery.normalise('').isSearchable, isFalse);
      expect(PlaceQuery.normalise('  ').isSearchable, isFalse);
      expect(PlaceQuery.normalise('io').isSearchable, isFalse);
      expect(PlaceQuery.normalise('ion').isSearchable, isTrue);
      expect(PlaceQuery.normalise('098585').isSearchable, isTrue);
    });
  });
}
