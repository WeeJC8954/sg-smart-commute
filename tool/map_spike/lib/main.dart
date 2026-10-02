// Phase 2 M0 map spike (throwaway). Proves, on Android and Web under the
// app's CSP: raster basemaps from OneMap / OSM / CARTO, markers, a bus-ride
// polyline sliced from busrouter routes.min.json, and a walking polyline from
// the FOSSGIS Valhalla pedestrian router. Not part of the app.
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

void main() => runApp(const SpikeApp());

class Basemap {
  const Basemap(
    this.name,
    this.url,
    this.attribution, {
    this.maxNative = 19,
    this.dark = false,
  });
  final String name;
  final String url;
  final String attribution;
  final int maxNative;
  final bool dark;
}

const basemaps = [
  Basemap(
    'OneMap Default',
    'https://www.onemap.gov.sg/maps/tiles/Default/{z}/{x}/{y}.png',
    'OneMap © contributors | Singapore Land Authority',
  ),
  Basemap(
    'OneMap Night',
    'https://www.onemap.gov.sg/maps/tiles/Night/{z}/{x}/{y}.png',
    'OneMap © contributors | Singapore Land Authority',
    dark: true,
  ),
  Basemap(
    'OSM standard',
    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    '© OpenStreetMap contributors',
  ),
  Basemap(
    'CARTO Positron',
    'https://a.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
    '© OpenStreetMap contributors © CARTO',
    maxNative: 20,
  ),
  Basemap(
    'CARTO Dark Matter',
    'https://a.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
    '© OpenStreetMap contributors © CARTO',
    maxNative: 20,
    dark: true,
  ),
];

// The M3 smoke journey: Raffles Place -> VivoCity, Bus 10 from 03019 to 14141.
const origin = LatLng(1.2840, 103.8515);
const destination = LatLng(1.2644, 103.8222);
const service = '10', boardCode = '03019', alightCode = '14141';

class SpikeApp extends StatefulWidget {
  const SpikeApp({super.key});
  @override
  State<SpikeApp> createState() => _SpikeAppState();
}

class _SpikeAppState extends State<SpikeApp> {
  // ?src=N picks the basemap (for headless screenshots).
  int _source = int.tryParse(Uri.base.queryParameters['src'] ?? '') ?? 0;
  int _tileErrors = 0;
  String _status = 'loading busrouter + Valhalla…';
  List<LatLng> _ride = const [];
  List<LatLng> _walk = const [];
  LatLng? _board, _alight;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final sw = Stopwatch()..start();
      Future<Map<String, dynamic>> get(String f) async => jsonDecode(
        (await http.get(Uri.parse('https://data.busrouter.sg/v1/$f.min.json')))
            .body,
      ) as Map<String, dynamic>;
      final [routes, services, stops] = await Future.wait([
        get('routes'),
        get('services'),
        get('stops'),
      ]);
      LatLng stop(String c) {
        final s = stops[c] as List;
        return LatLng(
          (s[1] as num).toDouble(),
          (s[0] as num).toDouble(),
        ); // busrouter is [lng, lat]
      }

      final dirs = (services[service]['routes'] as List).cast<List>();
      final di = dirs.indexWhere(
        (d) =>
            d.contains(boardCode) &&
            d.indexOf(boardCode) < d.indexOf(alightCode),
      );
      final line = decodePolyline((routes[service] as List)[di] as String, 5);
      final board = stop(boardCode), alight = stop(alightCode);
      final ride = slice(line, board, alight);
      final fetchMs = sw.elapsedMilliseconds;

      final q = jsonEncode({
        'locations': [
          {'lat': origin.latitude, 'lon': origin.longitude},
          {'lat': board.latitude, 'lon': board.longitude},
        ],
        'costing': 'pedestrian',
      });
      final v = jsonDecode(
        (await http.get(
          Uri.https('valhalla1.openstreetmap.de', '/route', {'json': q}),
        )).body,
      );
      final leg = v['trip']['legs'][0];
      final walk = decodePolyline(leg['shape'] as String, 6);
      setState(() {
        _board = board;
        _alight = alight;
        _ride = ride;
        _walk = walk;
        _status =
            'busrouter ${fetchMs}ms: line ${line.length} pts, ride slice ${ride.length} pts; '
            'Valhalla walk ${(leg['summary']['length'] as num).toStringAsFixed(2)} km, ${walk.length} pts';
      });
      debugPrint('[spike] $_status');
    } catch (e) {
      setState(() => _status = 'load failed: $e');
      debugPrint('[spike] load failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = basemaps[_source];
    final scheme = ColorScheme.fromSeed(
      seedColor: Colors.teal,
      brightness: b.dark ? Brightness.dark : Brightness.light,
    );
    return MaterialApp(
      theme: ThemeData(colorScheme: scheme),
      home: Scaffold(
        appBar: AppBar(title: Text('Map spike: ${b.name}')),
        body: Column(
          children: [
            Wrap(
              spacing: 4,
              children: [
                for (var i = 0; i < basemaps.length; i++)
                  ChoiceChip(
                    label: Text(basemaps[i].name),
                    selected: i == _source,
                    onSelected: (_) => setState(() {
                      _source = i;
                      _tileErrors = 0;
                    }),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(4),
              child: Text(
                '$_status | tile errors: $_tileErrors',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            Expanded(
              child: FlutterMap(
                options: MapOptions(
                  initialCameraFit: CameraFit.bounds(
                    bounds: LatLngBounds.fromPoints([origin, destination]),
                    padding: const EdgeInsets.all(40),
                  ),
                  minZoom: 11,
                  maxZoom: 19,
                  // Singapore only.
                  cameraConstraint: CameraConstraint.contain(
                    bounds: LatLngBounds(
                      const LatLng(1.15, 103.55),
                      const LatLng(1.48, 104.10),
                    ),
                  ),
                ),
                children: [
                  TileLayer(
                    key: ValueKey(b.url),
                    urlTemplate: b.url,
                    maxNativeZoom: b.maxNative,
                    retinaMode:
                        b.url.contains('{r}') &&
                        RetinaMode.isHighDensity(context),
                    userAgentPackageName: 'sg.smartcommute.spike',
                    errorTileCallback: (tile, error, _) {
                      debugPrint(
                        '[spike] tile error ${tile.coordinates}: $error',
                      );
                      WidgetsBinding.instance.addPostFrameCallback(
                        (_) => setState(() => _tileErrors++),
                      );
                    },
                  ),
                  PolylineLayer(
                    polylines: [
                      if (_walk.isNotEmpty)
                        Polyline(
                          points: _walk,
                          strokeWidth: 4,
                          color: Colors.orange,
                          pattern: StrokePattern.dotted(),
                        ),
                      if (_board != null)
                        Polyline(
                          points: [_alight!, destination],
                          strokeWidth: 3,
                          color: Colors.grey,
                          pattern: StrokePattern.dashed(segments: const [8, 6]),
                        ),
                      if (_ride.isNotEmpty)
                        Polyline(
                          points: _ride,
                          strokeWidth: 5,
                          color: scheme.primary,
                        ),
                    ],
                  ),
                  MarkerLayer(
                    markers: [
                      _pin(origin, Icons.my_location, Colors.blue),
                      _pin(destination, Icons.flag, Colors.red),
                      if (_board != null)
                        _pin(_board!, Icons.directions_bus, scheme.primary),
                      if (_alight != null)
                        _pin(_alight!, Icons.place, scheme.tertiary),
                    ],
                  ),
                  RichAttributionWidget(
                    alignment: AttributionAlignment.bottomLeft,
                    attributions: [
                      TextSourceAttribution(b.attribution),
                      const TextSourceAttribution(
                        'Bus routes: busrouter.sg (data © LTA)',
                      ),
                      const TextSourceAttribution(
                        'Walking route: Valhalla (FOSSGIS), © OpenStreetMap contributors',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Marker _pin(LatLng p, IconData icon, Color c) => Marker(
    point: p,
    width: 32,
    height: 32,
    child: Icon(icon, color: c, size: 28),
  );
}

/// Google encoded polyline (busrouter: precision 5; Valhalla: 6).
List<LatLng> decodePolyline(String s, int precision) {
  final f = math.pow(10, precision).toDouble();
  final out = <LatLng>[];
  var i = 0, lat = 0, lng = 0;
  int next() {
    var shift = 0, result = 0, b = 0;
    do {
      b = s.codeUnitAt(i++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    // Not ~(result >> 1): dart2js bitwise ops are unsigned 32-bit, so ~ would
    // turn every negative delta into ~2^32 on Web.
    return (result & 1) != 0 ? -(result >> 1) - 1 : result >> 1;
  }

  while (i < s.length) {
    lat += next();
    lng += next();
    out.add(LatLng(lat / f, lng / f));
  }
  return out;
}

/// The part of [line] between the projections of [a] and [b] (spike-grade:
/// nearest projection, no ordering guard).
List<LatLng> slice(List<LatLng> line, LatLng a, LatLng b) {
  (int, LatLng) nearest(LatLng p) {
    var best = (0, line.first);
    var bestD = double.infinity;
    for (var k = 0; k + 1 < line.length; k++) {
      final q = _project(p, line[k], line[k + 1]);
      final c = math.cos(p.latitude * math.pi / 180);
      final dx = (p.longitude - q.longitude) * c, dy = p.latitude - q.latitude;
      final d = dx * dx + dy * dy; // planar, for comparison only
      if (d < bestD) {
        bestD = d;
        best = (k, q);
      }
    }
    return best;
  }

  final (ia, pa) = nearest(a);
  final (ib, pb) = nearest(b);
  return [pa, ...line.sublist(ia + 1, ib + 1), pb];
}

LatLng _project(LatLng p, LatLng a, LatLng b) {
  final k = math.cos(p.latitude * math.pi / 180);
  final ax = a.longitude * k,
      ay = a.latitude,
      bx = b.longitude * k,
      by = b.latitude;
  final px = p.longitude * k, py = p.latitude;
  final dx = bx - ax, dy = by - ay, l2 = dx * dx + dy * dy;
  final t = l2 == 0
      ? 0.0
      : (((px - ax) * dx + (py - ay) * dy) / l2).clamp(0.0, 1.0);
  return LatLng(ay + t * dy, (ax + t * dx) / k);
}
