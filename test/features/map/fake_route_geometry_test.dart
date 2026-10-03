// The shared fake encoder (integration_test/fakes/) against the production
// decoder. Kept apart from polyline_codec_test.dart so that file imports
// nothing from integration_test/ and also compiles for a Chrome test run.
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/core/geo/geo.dart';
import 'package:sg_smart_commute/features/map/domain/polyline_codec.dart';

import '../../../integration_test/fakes/fake_route_geometry.dart';

void main() {
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
