import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../geo/geo.dart';
import 'geolocator_location_service.dart';

/// Outcome of the permission step (guide §5.1 step 4).
enum LocationAccess { granted, denied, deniedForever, serviceDisabled }

/// Seam over the platform location APIs, so the permission → timeout →
/// late-fix state machine can be tested with a fake.
abstract interface class LocationService {
  /// Checks the location service and permission, requesting it if needed.
  Future<LocationAccess> requestAccess();

  /// One position fix. Has no timeout of its own: the caller applies the
  /// acquisition timeout and still accepts a late result (§5.4).
  /// Throws a `LocationFailure` on error.
  Future<LatLng> currentPosition();

  /// Opens app settings (permission blocked) or location settings (service
  /// off), where the platform supports it.
  Future<void> openSettings(LocationAccess reason);
}

final locationServiceProvider = Provider<LocationService>(
  (ref) => const GeolocatorLocationService(),
);
