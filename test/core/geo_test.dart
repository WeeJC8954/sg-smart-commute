import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/core/geo/geo.dart';

void main() {
  group('isWithinTransportBounds', () {
    test('accepts the edges (inclusive) and rejects just outside', () {
      expect(isWithinTransportBounds(const LatLng(1.10, 103.50)), isTrue);
      expect(isWithinTransportBounds(const LatLng(1.60, 104.20)), isTrue);
      expect(isWithinTransportBounds(const LatLng(1.099, 103.8)), isFalse);
      expect(isWithinTransportBounds(const LatLng(1.601, 103.8)), isFalse);
      expect(isWithinTransportBounds(const LatLng(1.3, 103.499)), isFalse);
      expect(isWithinTransportBounds(const LatLng(1.3, 104.201)), isFalse);
    });

    test('rejects swapped lat/lng and non-finite values', () {
      expect(isWithinTransportBounds(const LatLng(103.8, 1.35)), isFalse);
      expect(isWithinTransportBounds(const LatLng(double.nan, 103.8)), isFalse);
      expect(
        isWithinTransportBounds(const LatLng(1.3, double.infinity)),
        isFalse,
      );
    });
  });

  group('isWithinSingapore (guide §5.2)', () {
    test('accepts points inside the box', () {
      expect(
        isWithinSingapore(const LatLng(1.3508, 103.8485)),
        isTrue,
      ); // Bishan
      expect(
        isWithinSingapore(const LatLng(1.2644, 103.8222)),
        isTrue,
      ); // VivoCity
    });

    test('accepts the box edges (inclusive)', () {
      expect(isWithinSingapore(const LatLng(1.15, 103.60)), isTrue);
      expect(isWithinSingapore(const LatLng(1.48, 104.10)), isTrue);
    });

    test('rejects points just outside each edge', () {
      expect(isWithinSingapore(const LatLng(1.149, 103.8)), isFalse);
      expect(isWithinSingapore(const LatLng(1.481, 103.8)), isFalse);
      expect(isWithinSingapore(const LatLng(1.3, 103.599)), isFalse);
      expect(isWithinSingapore(const LatLng(1.3, 104.101)), isFalse);
    });

    test('rejects the Android emulator default (Mountain View, US)', () {
      expect(isWithinSingapore(const LatLng(37.4220, -122.0841)), isFalse);
    });

    test('rejects swapped lat/lng', () {
      expect(isWithinSingapore(const LatLng(103.8485, 1.3508)), isFalse);
    });

    test('rejects non-finite values', () {
      expect(isWithinSingapore(const LatLng(double.nan, 103.8)), isFalse);
      expect(isWithinSingapore(const LatLng(1.3, double.nan)), isFalse);
      expect(isWithinSingapore(const LatLng(double.infinity, 103.8)), isFalse);
      expect(
        isWithinSingapore(const LatLng(1.3, double.negativeInfinity)),
        isFalse,
      );
    });
  });

  group('haversineMeters', () {
    test('is zero for the same point', () {
      expect(
        haversineMeters(const LatLng(1.3, 103.8), const LatLng(1.3, 103.8)),
        0,
      );
    });

    test('one degree of latitude is about 111.2 km', () {
      final d = haversineMeters(const LatLng(1, 103.8), const LatLng(2, 103.8));
      expect(d, closeTo(111195, 50));
    });

    test('is symmetric', () {
      const a = LatLng(1.3508, 103.8485);
      const b = LatLng(1.2644, 103.8222);
      expect(haversineMeters(a, b), closeTo(haversineMeters(b, a), 1e-6));
      // Bishan to VivoCity is roughly 10 km.
      expect(haversineMeters(a, b), closeTo(10040, 150));
    });
  });
}
