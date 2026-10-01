import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/features/environment/domain/bands.dart';

void main() {
  test('24-hr PSI bands (NEA haze.gov.sg)', () {
    expect(psiBand(0), 'Good');
    expect(psiBand(50), 'Good');
    expect(psiBand(51), 'Moderate');
    expect(psiBand(100), 'Moderate');
    expect(psiBand(101), 'Unhealthy');
    expect(psiBand(200), 'Unhealthy');
    expect(psiBand(201), 'Very unhealthy');
    expect(psiBand(300), 'Very unhealthy');
    expect(psiBand(301), 'Hazardous');
  });

  test('1-hr PM2.5 bands (NEA haze.gov.sg)', () {
    expect(pm25Band(0), 'Normal');
    expect(pm25Band(55), 'Normal');
    expect(pm25Band(56), 'Elevated');
    expect(pm25Band(150), 'Elevated');
    expect(pm25Band(151), 'High');
    expect(pm25Band(250), 'High');
    expect(pm25Band(251), 'Very high');
  });

  test('UV index categories (NEA)', () {
    expect(uvBand(0), 'Low');
    expect(uvBand(2), 'Low');
    expect(uvBand(3), 'Moderate');
    expect(uvBand(5), 'Moderate');
    expect(uvBand(6), 'High');
    expect(uvBand(7), 'High');
    expect(uvBand(8), 'Very high');
    expect(uvBand(10), 'Very high');
    expect(uvBand(11), 'Extreme');
    expect(uvBand(14), 'Extreme');
  });

  test('negative readings have no band', () {
    expect(psiBand(-1), isNull);
    expect(pm25Band(-1), isNull);
    expect(uvBand(-1), isNull);
  });
}
