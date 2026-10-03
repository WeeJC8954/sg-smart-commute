import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/core/geo/geo.dart';
import 'package:sg_smart_commute/features/map/domain/polyline_codec.dart';

import '../../../integration_test/fakes/fake_route_geometry.dart';

void main() {
  test('Google reference polyline: positive and negative deltas', () {
    // https://developers.google.com/maps/documentation/utilities/polylinealgorithm
    final points = decodePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@');
    expect(points.length, 3);
    void near(LatLng p, double lat, double lng) {
      expect(p.latitude, closeTo(lat, 1e-9));
      expect(p.longitude, closeTo(lng, 1e-9));
    }

    near(points[0], 38.5, -120.2);
    near(points[1], 40.7, -120.95); // negative longitude delta
    near(points[2], 43.252, -126.453);
  });

  test('a large negative delta is decoded exactly '
      '(would be ~2^32 off with ~(r >> 1) under dart2js)', () {
    // (1.3, 103.8) then (1.25, 103.75): deltas -5000 / -5000 in 1e-5 units.
    final points = decodePolyline('_||F_mpxRnwHnwH');
    expect(points[0].latitude, closeTo(1.3, 1e-9));
    expect(points[0].longitude, closeTo(103.8, 1e-9));
    expect(points[1].latitude, closeTo(1.25, 1e-9));
    expect(points[1].longitude, closeTo(103.75, 1e-9));
  });

  test('empty string decodes to no points', () {
    expect(decodePolyline(''), isEmpty);
  });

  for (final (why, s) in [
    ('truncated (continuation bit at the end)', '_p~iF~ps|U_'),
    ('a latitude without a longitude', '_p~iF'),
    ('a character below "?"', '_p~iF~ps|U '),
    ('a value longer than 32 bits', '~~~~~~~~~~'),
  ]) {
    test('malformed: $why → FormatException', () {
      expect(() => decodePolyline(s), throwsFormatException);
    });
  }

  test('the shared fake encoder is the exact inverse, negative deltas too', () {
    // The Google reference polyline, then a track that heads south-west.
    expect(
      encodePolyline(const [
        LatLng(38.5, -120.2),
        LatLng(40.7, -120.95),
        LatLng(43.252, -126.453),
      ]),
      '_p~iF~ps|U_ulLnnqC_mqNvxq`@',
    );
    const track = [LatLng(1.3510, 103.8490), LatLng(1.2645, 103.8226)];
    final back = decodePolyline(encodePolyline(track));
    expect(back.length, 2);
    for (var i = 0; i < 2; i++) {
      expect(back[i].latitude, closeTo(track[i].latitude, 1e-9));
      expect(back[i].longitude, closeTo(track[i].longitude, 1e-9));
    }
  });
}
