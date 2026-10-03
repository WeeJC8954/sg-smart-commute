import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../../core/config/app_config.dart';
import '../../../core/geo/geo.dart';
import '../domain/map_scene.dart';
import '../domain/ride_geometry.dart';
import '../map_providers.dart';
import 'basemap.dart';

/// The journey on a OneMap basemap: markers (P2-M1) and the bus ride drawn on
/// its road when the route geometry matches it (P2-M2). Built only while
/// the user has the map open, so tiles are requested only for a visible map.
///
/// Reasonable use (docs/map-feasibility.md §4.2): the camera is fitted once
/// per journey without animation and cannot leave OneMap's bounds or zoom
/// range; failed tiles are not retried automatically.
class JourneyMap extends ConsumerStatefulWidget {
  const JourneyMap({super.key, required this.scene});

  final MapScene scene;

  static const String tilesUnavailable =
      'Map tiles are unavailable right now. The journey above is unaffected.';

  static const String rideLineUnavailable =
      "The bus route line isn't available for this ride. The stops are shown.";

  @override
  ConsumerState<JourneyMap> createState() => _JourneyMapState();
}

class _JourneyMapState extends ConsumerState<JourneyMap> {
  final _controller = MapController();
  late final TileProvider _tiles = ref.read(mapTileProviderFactoryProvider)();
  bool _ready = false;
  bool _tilesFailed = false;
  Brightness? _brightness;
  MapCamera? _initialCamera;

  static final _constraint = CameraConstraint.contain(
    bounds: LatLngBounds(
      const ll.LatLng(MapConfig.boundsSouth, MapConfig.boundsWest),
      const ll.LatLng(MapConfig.boundsNorth, MapConfig.boundsEast),
    ),
  );

  static ll.LatLng _toMap(LatLng p) => ll.LatLng(p.latitude, p.longitude);

  static bool _isEnd(MapMarkerKind kind) =>
      kind == MapMarkerKind.origin || kind == MapMarkerKind.destination;

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
    // A new journey (or new stops for it): fit once, without animating.
    if (_ready && widget.scene != oldWidget.scene) {
      _controller.fitCamera(_fit(widget.scene));
    }
  }

  @override
  void dispose() {
    // The tile layer disposes the tile provider (and its HTTP client).
    _controller.dispose();
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

    // Also starts the one route-geometry load for a direct-bus ride (this is
    // only ever built while the map is open). The line is drawn only for the
    // ride this scene shows, never for a result worked out for another one.
    final rideLine = ref.watch(rideLineProvider);
    final drawn = switch (rideLine?.value) {
      final RideLineDrawn line when line.ride == widget.scene.ride => line,
      _ => null,
    };
    final rideUnavailable =
        widget.scene.ride != null &&
        (rideLine?.hasError == true || rideLine?.value is RideLineUnavailable);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: MapConfig.height,
          child: Semantics(
            container: true,
            label: widget.scene.summary,
            // Visual only: the journey card above is the accessible answer.
            child: ExcludeSemantics(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final initial = _initialCamera ??= _fittedCamera(
                    widget.scene,
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
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                      ),
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                      onMapReady: () => _ready = true,
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
                          // Ends first and larger, stops on top and smaller: where
                          // a stop is a short walk from an end, both stay visible.
                          for (final m in [
                            ...widget.scene.markers.where(
                              (m) => _isEnd(m.kind),
                            ),
                            ...widget.scene.markers.where(
                              (m) => !_isEnd(m.kind),
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
    };
    return Tooltip(
      message: marker.label,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surface,
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 2.5),
          boxShadow: const [BoxShadow(blurRadius: 3, color: Colors.black38)],
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
