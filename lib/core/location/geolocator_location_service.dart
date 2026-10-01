import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../errors/app_failure.dart';
import '../geo/geo.dart';
import 'location_service.dart';

/// [LocationService] backed by the `geolocator` plugin (Android + Web).
///
/// Thin adapter: it only maps plugin results and exceptions to domain types.
/// The timeout and Singapore-bounds rules live in the origin controller.
class GeolocatorLocationService implements LocationService {
  const GeolocatorLocationService();

  @override
  Future<LocationAccess> requestAccess() async {
    try {
      // The web implementation always reports "enabled"; a disabled browser
      // setting surfaces as a denied permission instead.
      if (!await Geolocator.isLocationServiceEnabled()) {
        return LocationAccess.serviceDisabled;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.unableToDetermine) {
        permission = await Geolocator.requestPermission();
      }
      return switch (permission) {
        LocationPermission.whileInUse ||
        LocationPermission.always => LocationAccess.granted,
        LocationPermission.deniedForever => LocationAccess.deniedForever,
        LocationPermission.denied ||
        LocationPermission.unableToDetermine => LocationAccess.denied,
      };
    } on PermissionDeniedException {
      return LocationAccess.denied;
    } on LocationServiceDisabledException {
      return LocationAccess.serviceDisabled;
    } catch (e) {
      if (kDebugMode) debugPrint('requestAccess failed: $e');
      return LocationAccess.denied;
    }
  }

  @override
  Future<LatLng> currentPosition() async {
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      return LatLng(p.latitude, p.longitude);
    } on LocationServiceDisabledException {
      throw const LocationServiceDisabled();
    } on PermissionDeniedException {
      throw const LocationPermissionDenied();
    } catch (e) {
      if (kDebugMode) debugPrint('currentPosition failed: $e');
      throw const LocationUnavailable();
    }
  }

  @override
  Future<void> openSettings(LocationAccess reason) async {
    if (kIsWeb) return; // Browsers have no settings deep link.
    if (reason == LocationAccess.serviceDisabled) {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
    }
  }
}
