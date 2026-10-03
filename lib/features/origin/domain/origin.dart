import '../../../core/errors/app_failure.dart';
import '../../../core/geo/geo.dart';

/// Where an origin came from (§5.4). Makes the late-fix rule testable.
enum OriginProvenance { gps, manual }

class Origin {
  const Origin({
    required this.position,
    required this.label,
    required this.provenance,
    this.detail,
  });

  final LatLng position;
  final String label;
  final OriginProvenance provenance;

  /// Address detail of a searched place (e.g. road + postcode), if any.
  final String? detail;
}

enum OriginPhase {
  /// Permission/service check in progress. The shell is already visible.
  checkingPermission,

  /// Permission granted; waiting for a fix within the timeout.
  acquiring,

  /// The manual origin prompt is shown (fallback, or the user chose "Change").
  needsManual,

  /// An origin is set.
  ready,
}

class OriginState {
  const OriginState({
    required this.phase,
    this.origin,
    this.fallbackReason,
    this.offeredGpsFix,
    this.manualEntryInProgress = false,
    this.locatingInBackground = false,
    this.backgroundFailure,
  });

  const OriginState.initial() : this(phase: OriginPhase.checkingPermission);

  final OriginPhase phase;

  /// The current origin, if any. Kept while the user is changing it.
  final Origin? origin;

  /// Why the manual prompt is shown. Null when the user opened it themselves.
  final LocationFailure? fallbackReason;

  /// A valid fix that arrived late and was not applied, because the user had
  /// chosen (or was choosing) an origin manually. Offered via a chip.
  final LatLng? offeredGpsFix;

  /// The user has started manual entry; a late fix must not overwrite it.
  final bool manualEntryInProgress;

  /// "Try location again" is running behind a manual origin. Its fix is only
  /// offered ([offeredGpsFix]); the manual origin stays in effect.
  final bool locatingInBackground;

  /// Why the last background attempt found no usable fix. Shown as a note;
  /// it never changes the origin.
  final LocationFailure? backgroundFailure;

  OriginState copyWith({
    OriginPhase? phase,
    Origin? origin,
    LocationFailure? fallbackReason,
    bool clearFallbackReason = false,
    LatLng? offeredGpsFix,
    bool? manualEntryInProgress,
    bool? locatingInBackground,
    LocationFailure? backgroundFailure,
    bool clearBackgroundFailure = false,
  }) => OriginState(
    phase: phase ?? this.phase,
    origin: origin ?? this.origin,
    fallbackReason: clearFallbackReason
        ? null
        : (fallbackReason ?? this.fallbackReason),
    offeredGpsFix: offeredGpsFix ?? this.offeredGpsFix,
    manualEntryInProgress: manualEntryInProgress ?? this.manualEntryInProgress,
    locatingInBackground: locatingInBackground ?? this.locatingInBackground,
    backgroundFailure: clearBackgroundFailure
        ? null
        : (backgroundFailure ?? this.backgroundFailure),
  );
}
