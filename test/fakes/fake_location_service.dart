import 'dart:async';

import 'package:sg_smart_commute/core/geo/geo.dart';
import 'package:sg_smart_commute/core/location/location_service.dart';

/// Controllable [LocationService] for unit, widget and integration tests.
///
/// The permission answer and the position are each completed by the test, so
/// it decides exactly when (and whether) they arrive.
class FakeLocationService implements LocationService {
  FakeLocationService({LocationAccess? access, LatLng? position}) {
    if (access != null) _access.complete(access);
    if (position != null) _position.complete(position);
  }

  Completer<LocationAccess> _access = Completer<LocationAccess>();
  Completer<LatLng> _position = Completer<LatLng>();

  int accessRequests = 0;
  int positionRequests = 0;
  final List<LocationAccess> settingsOpened = [];

  void grant() => _access.complete(LocationAccess.granted);
  void answer(LocationAccess access) => _access.complete(access);
  void fix(LatLng position) => _position.complete(position);
  void fail(Object error) => _position.completeError(error);

  /// Prepares fresh completers for a second attempt (e.g. "Try again").
  void reset() {
    _access = Completer<LocationAccess>();
    _position = Completer<LatLng>();
  }

  @override
  Future<LocationAccess> requestAccess() {
    accessRequests++;
    return _access.future;
  }

  @override
  Future<LatLng> currentPosition() {
    positionRequests++;
    return _position.future;
  }

  @override
  Future<void> openSettings(LocationAccess reason) async {
    settingsOpened.add(reason);
  }
}
