// Milestone 0 runtime probe: verifies the selected providers from a real
// Flutter runtime (Chrome enforces CORS; Android does not). Dev-only entry
// point, not part of the app:
//
//   flutter run -d chrome -t tool/api_probe_app.dart
//   flutter run -d <android-device> -t tool/api_probe_app.dart
//
// Each result is printed as a `PROBE` line and shown on screen.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const _probes = <(String, String)>[
  (
    'data.gov.sg two-hr-forecast',
    'https://api-open.data.gov.sg/v2/real-time/api/two-hr-forecast',
  ),
  ('data.gov.sg uv', 'https://api-open.data.gov.sg/v2/real-time/api/uv'),
  ('data.gov.sg pm25', 'https://api-open.data.gov.sg/v2/real-time/api/pm25'),
  ('data.gov.sg psi', 'https://api-open.data.gov.sg/v2/real-time/api/psi'),
  ('busrouter stops', 'https://data.busrouter.sg/v1/stops.min.json'),
  ('busrouter services', 'https://data.busrouter.sg/v1/services.min.json'),
  ('ArriveLah 09048', 'https://arrivelah2.busrouter.sg/?id=09048'),
  (
    'OneMap search (tokenless)',
    'https://www.onemap.gov.sg/api/common/elastic/search?searchVal=vivocity&returnGeom=Y&getAddrDetails=Y&pageNum=1',
  ),
  (
    'Photon search',
    'https://photon.komoot.io/api/?q=vivocity&bbox=103.6,1.15,104.1,1.48&limit=3',
  ),
  (
    'Nominatim search',
    'https://nominatim.openstreetmap.org/search?q=vivocity&countrycodes=sg&format=jsonv2&limit=3',
  ),
  (
    'LTA DataMall (expected to fail)',
    'https://datamall2.mytransport.sg/ltaodataservice/v3/BusArrival?BusStopCode=09048',
  ),
];

// Browsers forbid setting User-Agent; they send Referer instead, which the
// Nominatim policy accepts for web apps.
const _headers = kIsWeb
    ? <String, String>{}
    : {
        'User-Agent': 'sg-smart-commute-m0-probe/0.1 (https://github.com/WeeJC8954/sg-smart-commute)',
      };

void main() => runApp(const MaterialApp(home: ProbeScreen()));

class ProbeScreen extends StatefulWidget {
  const ProbeScreen({super.key});

  @override
  State<ProbeScreen> createState() => _ProbeScreenState();
}

class _ProbeScreenState extends State<ProbeScreen> {
  final _lines = <String>[];

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final platform = kIsWeb ? 'web' : defaultTargetPlatform.name;
    _log('PROBE START platform=$platform');
    for (final (name, url) in _probes) {
      final sw = Stopwatch()..start();
      try {
        final res = await http
            .get(Uri.parse(url), headers: _headers)
            .timeout(const Duration(seconds: 20));
        _log(
          'PROBE $name -> HTTP ${res.statusCode}, ${res.bodyBytes.length} bytes, ${sw.elapsedMilliseconds} ms',
        );
      } catch (e) {
        _log(
          'PROBE $name -> FAILED (${e.runtimeType}: ${'$e'.split('\n').first}) after ${sw.elapsedMilliseconds} ms',
        );
      }
      // Keep Nominatim at <= 1 request per second.
      await Future<void>.delayed(const Duration(milliseconds: 1100));
    }
    _log('PROBE DONE');
  }

  void _log(String line) {
    debugPrint(line);
    if (mounted) setState(() => _lines.add(line));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('M0 API probe')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [for (final l in _lines) Text(l)],
    ),
  );
}
