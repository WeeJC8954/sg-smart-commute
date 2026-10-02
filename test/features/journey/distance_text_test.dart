import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/features/journey/presentation/distance_text.dart';

void main() {
  test('metres below 1 km, rounded to whole metres', () {
    expect(distanceText(20), '20 m');
    expect(distanceText(800), '800 m');
    expect(distanceText(999.4), '999 m');
  });

  test('kilometres to one decimal, without a trailing .0', () {
    expect(distanceText(999.6), '1 km'); // rounds up into km, not "1000 m"
    expect(distanceText(1000), '1 km');
    expect(distanceText(1500), '1.5 km');
    expect(distanceText(1549), '1.5 km');
    expect(distanceText(2000), '2 km');
    expect(distanceText(2500), '2.5 km');
    expect(distanceText(12340), '12.3 km');
  });
}
