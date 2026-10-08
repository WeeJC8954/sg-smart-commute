import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../../core/config/app_config.dart';
import '../../../core/geo/geo.dart';
import '../../../core/ui/focus_landing.dart';
import '../domain/map_scene.dart';
import '../domain/ride_geometry.dart';
import '../map_providers.dart';
import 'basemap.dart';

/// The journey on a OneMap basemap: markers (P2-M1), the bus ride drawn on
/// its road when the route geometry matches it (P2-M2), and (P2-M3) straight
/// dashed walking connectors, the MRT suggestions and a small legend. It
/// shows the option the journey card has selected. Built only while the user
/// has the map open, so tiles are requested only for a visible map.
///
/// Reasonable use (docs/map-feasibility.md §4.2): the camera is fitted once
/// per scene change (a new journey, the user's option selection, or the MRT
/// suggestion settling), without animation and never periodically or on a
/// timer, and cannot leave OneMap's bounds or zoom range; failed tiles are
/// not retried automatically.
///
/// Reduced motion (P2-M4): with the system's setting on, a swipe stops
/// where the finger lifts and a double-tap zoom lands at once; every
/// gesture still works.
class JourneyMap extends ConsumerStatefulWidget {
  const JourneyMap({super.key, required this.scene});

  final MapScene scene;

  static const String tilesUnavailable =
      'Map tiles are unavailable right now. The journey above is unaffected.';

  static const String rideLineUnavailable =
      "The bus route line isn't available for this ride. The stops are shown.";

  /// Legend (P2-M3): the dashed walking connectors are estimates, not routes.
  static const String walkLegend = 'Walk (straight-line estimate)';

  /// Legend (P2-M3): the solid line is the shown bus's route.
  static String busLegend(String service) => 'Bus $service route';

  @override
  ConsumerState<JourneyMap> createState() => _JourneyMapState();
}

class _JourneyMapState extends ConsumerState<JourneyMap> {
  final _controller = MapController();
  late final TileProvider _tiles = ref.read(mapTileProviderFactoryProvider)();
  bool _ready = false;

  /// The scene the camera was last fitted to (the initial camera, then each
  /// refit), so a change is fitted exactly once, and the latest one wins.
  MapScene? _cameraScene;
  bool _tilesFailed = false;
  Brightness? _brightness;
  MapCamera? _initialCamera;

  static final _constraint = CameraConstraint.contain(
    bounds: LatLngBounds(
      const ll.LatLng(MapConfig.boundsSouth, MapConfig.boundsWest),
      const ll.LatLng(MapConfig.boundsNorth, MapConfig.boundsEast),
    ),
  );

  /// The map's keyboard focus (arrow keys pan). Only Tab reaches it, never
  /// the map itself; while it has focus the map shows a ring and screen
  /// readers are on its summary (#58).
  final _mapFocus = FocusNode(debugLabel: 'journey-map');

  /// flutter_map focuses the map as it appears by default.
  late final _keyboard = KeyboardOptions(
    autofocus: false,
    focusNode: _mapFocus,
  );

  /// Every gesture but rotation (P2-M1), with flutter_map's motion: the map
  /// glides on after a quick swipe and a double tap zooms over 200 ms.
  late final _interaction = InteractionOptions(
    flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
    keyboardOptions: _keyboard,
  );

  /// The same gestures for the system's reduce-motion setting (P2-M4): the
  /// map stops where the finger lifts, and a double-tap zoom lands at once.
  /// Under that setting the framework would otherwise play a fling 200×
  /// faster, so the map jumped on release.
  late final _reducedMotionInteraction = InteractionOptions(
    flags:
        InteractiveFlag.all &
        ~InteractiveFlag.rotate &
        ~InteractiveFlag.flingAnimation,
    doubleTapZoomDuration: Duration.zero,
    keyboardOptions: _keyboard,
  );

  static ll.LatLng _toMap(LatLng p) => ll.LatLng(p.latitude, p.longitude);

  static bool _isEnd(MapMarkerKind kind) =>
      kind == MapMarkerKind.origin || kind == MapMarkerKind.destination;

  static bool _isMrt(MapMarkerKind kind) =>
      kind == MapMarkerKind.mrtNearOrigin ||
      kind == MapMarkerKind.mrtNearDestination;

  CameraFit _fit(MapScene scene) {
    final b = scene.bounds;
    return CameraFit.bounds(
      bounds: LatLngBounds(_toMap(b.southWest), _toMap(b.northEast)),
      padding: const EdgeInsets.all(MapConfig.fitPadding),
      maxZoom: MapConfig.fitMaxZoom,
    );
  }

  /// The camera fitted to [scene] in a map of [size], worked out before the
  /// first frame. flutter_map applies `initialCameraFit` only after its first
  /// layout, and that first frame requests tiles at its default camera: seen
  /// live on Web, about 25 OneMap tiles per opening, all thrown away.
  MapCamera _fittedCamera(MapScene scene, Size size) {
    final start = MapCamera(
      crs: const Epsg3857(),
      center: _toMap(scene.bounds.southWest),
      zoom: MapConfig.minZoom,
      rotation: 0,
      nonRotatedSize: size,
      minZoom: MapConfig.minZoom,
      maxZoom: MapConfig.maxZoom,
    );
    final fitted = _fit(scene).fit(start);
    return _constraint.constrain(fitted) ?? fitted;
  }

  @override
  void didUpdateWidget(JourneyMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new scene (journey, selected option, settled MRT suggestion): fit
    // once, without animating. Before the map is ready, _onMapReady does it.
    if (_ready) _fitLatest();
  }

  /// The map is ready: fit the scene as it is now, which may be newer than
  /// the one the initial camera was worked out for.
  void _onMapReady() {
    _ready = true;
    _fitLatest();
  }

  void _fitLatest() {
    final scene = widget.scene;
    if (scene == _cameraScene) return;
    _cameraScene = scene;
    _controller.fitCamera(_fit(scene));
  }

  @override
  void dispose() {
    // The tile layer disposes the tile provider (and its HTTP client).
    _controller.dispose();
    _mapFocus.dispose();
    super.dispose();
  }

  void _onTileError(TileImage tile, Object error, StackTrace? _) {
    if (_tilesFailed) return;
    // Called while tiles load; update after this frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _tilesFailed = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    if (_brightness != null && _brightness != brightness) {
      // The other style is a different set of tiles: report its own errors.
      _tilesFailed = false;
    }
    _brightness = brightness;
    // Android "Remove animations", Web prefers-reduced-motion. flutter_map
    // reads the flags on every gesture but the double-tap duration only when
    // the map is created; a change while it is open leaves that zoom to the
    // framework's reduced timing (one frame) until the map is next opened.
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    // Also starts the one route-geometry load for a direct-bus ride (this is
    // only ever built while the map is open). The line is drawn only for the
    // ride this scene shows, never for a result worked out for another one.
    final rideLine = ref.watch(rideLineProvider);
    final drawn = switch (rideLine?.value) {
      final RideLineDrawn line when line.ride == widget.scene.ride => line,
      _ => null,
    };
    // A failed load is a note only once it is not being retried, and a worked
    // out gap only for the ride this scene shows (as for the drawn line).
    final walks = widget.scene.walks;
    final rideUnavailable =
        widget.scene.ride != null &&
        ((rideLine != null && rideLine.hasError && !rideLine.isLoading) ||
            switch (rideLine?.value) {
              final RideLineUnavailable gap => gap.ride == widget.scene.ride,
              _ => false,
            });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: MapConfig.height,
          child: ListenableBuilder(
            listenable: _mapFocus,
            builder: (context, map) => FocusRing(
              focused: _mapFocus.hasFocus,
              child: Semantics(
                container: true,
                label: widget.scene.summary,
                // The map's own focus node is excluded below. `focused: false`
                // would make it focusable (a Tab stop on Web).
                focused: _mapFocus.hasFocus ? true : null,
                child: map,
              ),
            ),
            // Visual only: the journey card above is the accessible answer.
            child: ExcludeSemantics(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final initial = _initialCamera ??= _fittedCamera(
                    _cameraScene = widget.scene,
                    constraints.biggest,
                  );
                  return FlutterMap(
                    key: const Key('journey-map'),
                    mapController: _controller,
                    options: MapOptions(
                      initialCenter: initial.center,
                      initialZoom: initial.zoom,
                      minZoom: MapConfig.minZoom,
                      maxZoom: MapConfig.maxZoom,
                      cameraConstraint: _constraint,
                      interactionOptions: reduceMotion
                          ? _reducedMotionInteraction
                          : _interaction,
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                      onMapReady: _onMapReady,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: basemapTemplateFor(brightness),
                        tileProvider: _tiles,
                        userAgentPackageName: MapConfig.userAgentPackageName,
                        minZoom: MapConfig.minZoom,
                        maxZoom: MapConfig.maxZoom,
                        maxNativeZoom: MapConfig.maxZoom.toInt(),
                        errorTileCallback: _onTileError,
                      ),
                      // Straight dashed estimates (P2-M3), under the bus line:
                      // dashes, width and colour all differ from it.
                      if (walks.isNotEmpty)
                        PolylineLayer(
                          key: const Key('map-walk-connectors'),
                          polylines: [
                            for (final w in walks)
                              Polyline(
                                points: [_toMap(w.from), _toMap(w.to)],
                                strokeWidth: 3,
                                pattern: _walkPattern,
                                color: theme.colorScheme.tertiary,
                                borderStrokeWidth: 1,
                                borderColor: theme.colorScheme.surface,
                              ),
                          ],
                        ),
                      // Before the markers, so the pins stay on top.
                      if (drawn != null)
                        PolylineLayer(
                          key: const Key('map-ride-line'),
                          polylines: [
                            Polyline(
                              points: [for (final p in drawn.points) _toMap(p)],
                              strokeWidth: 5,
                              color: theme.colorScheme.primary,
                              borderStrokeWidth: 2,
                              borderColor: theme.colorScheme.surface,
                            ),
                          ],
                        ),
                      MarkerLayer(
                        markers: [
                          // MRT first (informational, never hiding a journey
                          // pin), then the ends, larger, then the stops on top
                          // and smaller: where a stop is a short walk from an
                          // end, both stay visible.
                          for (final m in [
                            ...widget.scene.markers.where(
                              (m) => _isMrt(m.kind),
                            ),
                            ...widget.scene.markers.where(
                              (m) => _isEnd(m.kind),
                            ),
                            ...widget.scene.markers.where(
                              (m) => !_isEnd(m.kind) && !_isMrt(m.kind),
                            ),
                          ])
                            Marker(
                              key: Key('map-marker-${m.kind.name}'),
                              point: _toMap(m.position),
                              width: _isEnd(m.kind) ? 40 : 30,
                              height: _isEnd(m.kind) ? 40 : 30,
                              child: _MarkerPin(m),
                            ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
        if (drawn != null || walks.isNotEmpty)
          Padding(
            key: const Key('map-legend'),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                if (drawn != null)
                  _LegendEntry(
                    color: theme.colorScheme.primary,
                    dashed: false,
                    label: JourneyMap.busLegend(drawn.ride.service),
                  ),
                if (walks.isNotEmpty)
                  _LegendEntry(
                    color: theme.colorScheme.tertiary,
                    dashed: true,
                    label: JourneyMap.walkLegend,
                  ),
              ],
            ),
          ),
        // Below the map, not over it, so it never hides a marker.
        if (_tilesFailed)
          Semantics(
            liveRegion: true,
            child: Padding(
              key: const Key('map-tiles-unavailable'),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  Icon(
                    Icons.cloud_off,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      JourneyMap.tilesUnavailable,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (rideUnavailable)
          Semantics(
            liveRegion: true,
            child: Padding(
              key: const Key('map-ride-unavailable'),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  Icon(
                    Icons.route_outlined,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      JourneyMap.rideLineUnavailable,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// The walking connectors' dashes (P2-M3). Not const: StrokePattern.dashed
/// asserts on its list, which a constant expression cannot do.
final StrokePattern _walkPattern = StrokePattern.dashed(
  segments: const [10, 8],
);

/// One legend line: a short swatch of the line, solid or dashed, and its name.
class _LegendEntry extends StatelessWidget {
  const _LegendEntry({
    required this.color,
    required this.dashed,
    required this.label,
  });

  final Color color;
  final bool dashed;
  final String label;

  @override
  Widget build(BuildContext context) {
    Widget bar(double width) => SizedBox(
      width: width,
      height: 4,
      child: ColoredBox(color: color),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (dashed)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              bar(5),
              const SizedBox(width: 3),
              bar(5),
              const SizedBox(width: 3),
              bar(5),
            ],
          )
        else
          bar(21),
        const SizedBox(width: 8),
        Flexible(
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    );
  }
}

/// A round pin with an icon per kind, on the surface colour with a border, so
/// it stands out on both the light and the dark basemap.
class _MarkerPin extends StatelessWidget {
  const _MarkerPin(this.marker);

  final MapMarker marker;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (marker.kind) {
      MapMarkerKind.origin => (Icons.my_location, scheme.tertiary),
      MapMarkerKind.boarding => (Icons.directions_bus, scheme.primary),
      MapMarkerKind.alighting => (Icons.logout, scheme.primary),
      MapMarkerKind.destination => (Icons.place, scheme.tertiary),
      MapMarkerKind.mrtNearOrigin ||
      MapMarkerKind.mrtNearDestination => (Icons.train, scheme.secondary),
    };
    return Tooltip(
      message: marker.label,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surface,
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 2.5),
          boxShadow: [
            BoxShadow(
              blurRadius: 3,
              color: scheme.shadow.withValues(alpha: 0.38),
            ),
          ],
        ),
        child: Center(
          child: FractionallySizedBox(
            widthFactor: 0.55,
            heightFactor: 0.55,
            child: FittedBox(child: Icon(icon, color: color)),
          ),
        ),
      ),
    );
  }
}
