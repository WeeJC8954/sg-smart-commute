import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/geo/geo.dart';
import '../../../core/location/location_service.dart';
import 'origin.dart';

/// Acquisition timeout. Injected so tests drive it with fake time.
final locationTimeoutProvider = Provider<Duration>(
  (ref) => AppTimings.locationTimeout,
);

final originControllerProvider =
    NotifierProvider<OriginController, OriginState>(OriginController.new);

/// Permission → timeout → fallback → late-fix state machine (guide §5.1–§5.4).
///
/// - denied / permanently denied / service disabled → manual prompt at once;
/// - granted → the timeout starts, then a position is requested;
/// - no valid fix before the timeout, an error, or a fix outside Singapore →
///   manual prompt;
/// - a valid fix never overwrites a manual origin (or one being entered), from
///   any attempt and whether in time or late: it is offered instead. If
///   nothing was chosen, it populates the origin;
/// - with a manual origin set, failures (denied, timeout, error, outside
///   Singapore) leave the state untouched, and "Try location again" runs in
///   the background: only [useCurrentLocation] switches back to GPS;
/// - each attempt has an id; a superseded attempt's results and timer are
///   ignored, so they are never applied as the current attempt's.
class OriginController extends Notifier<OriginState> {
  static const String currentLocationLabel = 'Current location';

  Timer? _timeout;

  /// Incremented per attempt so results of an abandoned attempt are ignored.
  int _attempt = 0;

  @override
  OriginState build() {
    ref.onDispose(() => _timeout?.cancel());
    _start();
    return const OriginState.initial();
  }

  LocationService get _service => ref.read(locationServiceProvider);

  Future<void> _start() async {
    final attempt = ++_attempt;
    _timeout?.cancel();

    final LocationAccess access;
    try {
      access = await _service.requestAccess();
    } catch (_) {
      if (_isCurrent(attempt)) _fallBack(const LocationUnavailable());
      return;
    }
    if (!_isCurrent(attempt)) return;

    switch (access) {
      case LocationAccess.denied:
        return _fallBack(const LocationPermissionDenied());
      case LocationAccess.deniedForever:
        return _fallBack(const LocationPermissionPermanentlyDenied());
      case LocationAccess.serviceDisabled:
        return _fallBack(const LocationServiceDisabled());
      case LocationAccess.granted:
        break;
    }

    if (!_hasManualOrigin) {
      state = state.copyWith(
        phase: OriginPhase.acquiring,
        clearFallbackReason: true,
      );
    }
    _timeout = Timer(ref.read(locationTimeoutProvider), () {
      if (_isCurrent(attempt) && state.phase == OriginPhase.acquiring) {
        _fallBack(const LocationTimeout());
      }
    });

    try {
      final fix = await _service.currentPosition();
      if (_isCurrent(attempt)) _onFix(fix);
    } catch (e) {
      if (!_isCurrent(attempt) || state.phase != OriginPhase.acquiring) {
        return; // late error
      }
      _timeout?.cancel();
      _fallBack(e is LocationFailure ? e : const LocationUnavailable());
    }
  }

  bool _isCurrent(int attempt) => ref.mounted && attempt == _attempt;

  bool get _hasManualOrigin =>
      state.origin?.provenance == OriginProvenance.manual;

  void _fallBack(LocationFailure reason) {
    _timeout?.cancel();
    // A manual origin is never disturbed by a failed attempt.
    if (_hasManualOrigin) return;
    state = OriginState(
      phase: OriginPhase.needsManual,
      origin: state.origin,
      fallbackReason: reason,
      manualEntryInProgress: state.manualEntryInProgress,
    );
  }

  void _onFix(LatLng fix) {
    final inTime = state.phase == OriginPhase.acquiring;
    if (!isWithinSingapore(fix)) {
      // Out of bounds counts as "unavailable"; a late one is simply dropped.
      if (inTime) _fallBack(const LocationOutsideSingapore());
      return;
    }
    if (inTime) {
      _timeout?.cancel();
      return _setGpsOrigin(fix);
    }

    if (_hasManualOrigin || state.manualEntryInProgress) {
      state = state.copyWith(offeredGpsFix: fix);
    } else {
      _setGpsOrigin(fix);
    }
  }

  void _setGpsOrigin(LatLng fix) {
    state = OriginState(
      phase: OriginPhase.ready,
      origin: Origin(
        position: fix,
        label: currentLocationLabel,
        provenance: OriginProvenance.gps,
      ),
    );
  }

  /// The user started manual entry (focused or typed in the origin search).
  void beginManualEntry() {
    if (state.phase == OriginPhase.needsManual &&
        !state.manualEntryInProgress) {
      state = state.copyWith(manualEntryInProgress: true);
    }
  }

  /// The user explicitly selected an origin (a place-search result). Throws
  /// [ArgumentError] if it is outside Singapore.
  void selectManualOrigin(String label, LatLng position, {String? detail}) {
    if (!isWithinSingapore(position)) {
      throw ArgumentError.value(position, 'position', 'outside Singapore');
    }
    // A fix still pending from this attempt may arrive later. With a manual
    // origin set, it becomes an offer, never an overwrite.
    _timeout?.cancel();
    state = OriginState(
      phase: OriginPhase.ready,
      origin: Origin(
        position: position,
        label: label,
        provenance: OriginProvenance.manual,
        detail: detail,
      ),
      offeredGpsFix: state.offeredGpsFix,
    );
  }

  /// The user tapped "Use my current location" on an offered late fix.
  void useCurrentLocation() {
    final fix = state.offeredGpsFix;
    if (fix != null) _setGpsOrigin(fix);
  }

  /// Reopen the manual prompt to change the origin; the current one stays
  /// in effect until a new one is chosen.
  void changeOrigin() {
    state = state.copyWith(
      phase: OriginPhase.needsManual,
      clearFallbackReason: true,
      manualEntryInProgress: true,
    );
  }

  /// Run the permission/acquisition flow again (e.g. after enabling location).
  ///
  /// With a manual origin set, the attempt runs in the background: the manual
  /// origin stays in effect, a valid fix is only offered, and a failure is
  /// dropped. Without one, the flow runs as at launch.
  void retryLocation() {
    if (_hasManualOrigin) {
      state = state.copyWith(
        phase: OriginPhase.ready,
        clearFallbackReason: true,
        manualEntryInProgress: false,
      );
      _start();
      return;
    }
    state = OriginState(
      phase: OriginPhase.checkingPermission,
      origin: state.origin,
    );
    _start();
  }

  Future<void> openSettings() async {
    final access = switch (state.fallbackReason) {
      LocationServiceDisabled() => LocationAccess.serviceDisabled,
      LocationPermissionPermanentlyDenied() => LocationAccess.deniedForever,
      _ => LocationAccess.denied,
    };
    await _service.openSettings(access);
  }
}
