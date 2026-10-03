import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../../core/config/app_config.dart';
import '../../../core/geo/geo.dart';
import '../domain/map_scene.dart';
import 'basemap.dart';

/// The journey on a OneMap basemap: markers only (P2-M1). Built only while
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

  @override
  ConsumerState<JourneyMap> createState() => _JourneyMapState();
}

class _JourneyMapState extends ConsumerState<JourneyMap> {
  final _controller = MapController();
  late final TileProvider _tiles = ref.read(mapTileProviderFactoryProvider)();
  bool _ready = false;
  bool _tilesFailed = false;
  Brightness? _brightness;

  static final _cameraBounds = LatLngBounds(
    const ll.LatLng(MapConfig.boundsSouth, MapConfig.boundsWest),
    const ll.LatLng(MapConfig.boundsNorth, MapConfig.boundsEast),
  );

  static ll.LatLng _toMap(LatLng p) => ll.LatLng(p.latitude, p.longitude);

  CameraFit _fit(MapScene scene) {
    final b = scene.bounds;
    return CameraFit.bounds(
      bounds: LatLngBounds(_toMap(b.southWest), _toMap(b.northEast)),
      padding: const EdgeInsets.all(MapConfig.fitPadding),
      maxZoom: MapConfig.fitMaxZoom,
    );
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

    return Stack(
      children: [
        Semantics(
          container: true,
          label: widget.scene.summary,
          // Visual only: the journey card above is the accessible answer.
          child: ExcludeSemantics(
            child: FlutterMap(
              key: const Key('journey-map'),
              mapController: _controller,
              options: MapOptions(
                initialCameraFit: _fit(widget.scene),
                minZoom: MapConfig.minZoom,
                maxZoom: MapConfig.maxZoom,
                cameraConstraint: CameraConstraint.contain(
                  bounds: _cameraBounds,
                ),
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
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
                MarkerLayer(
                  markers: [
                    for (final m in widget.scene.markers)
                      Marker(
                        key: Key('map-marker-${m.kind.name}'),
                        point: _toMap(m.position),
                        width: 36,
                        height: 36,
                        child: _MarkerPin(m),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (_tilesFailed)
          Positioned(
            left: 8,
            right: 8,
            top: 8,
            child: Semantics(
              liveRegion: true,
              child: Material(
                key: const Key('map-tiles-unavailable'),
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(8),
                elevation: 1,
                child: Padding(
                  padding: const EdgeInsets.all(8),
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
        child: Center(child: Icon(icon, size: 20, color: color)),
      ),
    );
  }
}
