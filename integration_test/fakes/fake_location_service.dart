import 'dart:async';

import 'package:sg_smart_commute/core/geo/geo.dart';
import 'package:sg_smart_commute/core/location/location_service.dart';

/// Controllable [LocationService] for unit, widget and integration tests.
///
/// The permission answer and the position are each completed by the test, so
/// it decides exactly when (and whether) they arrive.
class FakeLocationService implements LocationService {
  FakeLocationService({LocationAccess? access, LatLng? position}) {
    _positions.add(_position);
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

  /// Makes the current attempt's permission request throw.
  void failAccess(Object error) => _access.completeError(error);

  /// The current attempt's permission completer, so a test can answer it
  /// after [reset] has started a newer attempt.
  Completer<LocationAccess> get pendingAccess => _access;
  void fix(LatLng position) => _position.complete(position);
  void fail(Object error) => _position.completeError(error);

  /// Position completers of every attempt, oldest first; index 0 is the
  /// launch attempt. Lets a test complete a superseded attempt late.
  final List<Completer<LatLng>> _positions = [];

  /// Prepares fresh completers for a second attempt (e.g. "Try again").
  void reset() {
    _access = Completer<LocationAccess>();
    _position = Completer<LatLng>();
    _positions.add(_position);
  }

  /// Completes attempt [attempt]'s position request (0 = launch attempt).
  void fixAttempt(int attempt, LatLng position) =>
      _positions[attempt].complete(position);

  /// Fails attempt [attempt]'s position request (0 = launch attempt).
  void failAttempt(int attempt, Object error) =>
      _positions[attempt].completeError(error);

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
