// Hand-made synthetic busrouter data for the parser, planner and ride-line
// tests (owner decision A-1, docs/busrouter-fixture-licensing-audit.md). It
// replaces subsets of the live files, whose redistribution rights could not
// be established. Nothing here is copied from busrouter, LTA or any other
// source: codes start with F, names end in "(fake)", and every position is
// laid out below in metres from a fixed origin. The maps have the live files'
// shapes (stops `{code: [lng, lat, name, road]}`, services `{number: {name,
// routes}}`, routes `{number: [encoded polyline per direction]}`), and each
// service is built for the edge case its tests need (README.md here).
import 'dart:convert';
import 'dart:math' as math;

import 'package:sg_smart_commute/core/geo/geo.dart';

import '../../../integration_test/fakes/fake_route_geometry.dart'
    show encodePolyline;

const double _metresPerDegree = 111195;

/// [north] and [east] metres from ([lat0], [lng0]), rounded to 5 decimals
/// like busrouter's positions (and the polyline encoding).
LatLng _at(double lat0, double lng0, double north, double east) {
  double r5(double v) => (v * 1e5).round() / 1e5;
  return LatLng(
    r5(lat0 + north / _metresPerDegree),
    r5(lng0 + east / (_metresPerDegree * math.cos(lat0 * math.pi / 180))),
  );
}

class _Builder {
  final stops = <String, List<Object>>{};
  final services = <String, Map<String, Object>>{};
  final routes = <String, List<String>>{};

  String stop(String code, LatLng p, String name, {String road = 'Fake Rd'}) {
    stops[code] = [p.longitude, p.latitude, '$name (fake)', road];
    return code;
  }

  LatLng pos(String code) {
    final s = stops[code]!;
    return LatLng(s[1] as double, s[0] as double);
  }

  void service(String number, List<List<String>> directions) =>
      services[number] = {
        'name': 'Synthetic $number (fake)',
        'routes': directions,
      };

  void line(String number, List<List<LatLng>> directions) =>
      routes[number] = [for (final d in directions) encodePolyline(d)];
}

// ---------------------------------------------------------------------------
// Planner network (busrouter_test.dart): six services, each in its own area.

final _Builder _network = () {
  final b = _Builder();

  // F4, a one-direction loop from and back to F0400 "Loop Int". Out along the
  // north side of a road (400 m apart), round at index 14, back along the
  // south side: the stop at index 22 is opposite the one at index 5, 29.1 m
  // apart. 28 entries, the terminal at 0 and 27.
  {
    LatLng p(double n, double e) => _at(1.35, 103.94, n, e);
    final terminal = b.stop('F0400', p(0, 0), 'Loop Int');
    final codes = <String>[terminal];
    for (var k = 1; k <= 13; k++) {
      codes.add(b.stop('F04${k + 10}', p(14.57, k * 400.0), 'Loop out $k'));
    }
    codes.add(b.stop('F0424', p(0, 5600), 'Loop turn'));
    for (var m = 15; m <= 26; m++) {
      codes.add(
        b.stop('F04${m + 30}', p(-14.57, (27 - m) * 400.0), 'Loop back $m'),
      );
    }
    codes.add(terminal);
    b.service('F4', [codes]);
  }

  // F184, one direction only: 45 stops in a straight line, 350 m apart.
  {
    final codes = [
      for (var k = 0; k < 45; k++)
        b.stop(
          'F18${k.toString().padLeft(3, '0')}',
          _at(1.427, 103.70, 0, k * 350.0),
          'One way $k',
        ),
    ];
    b.service('F184', [codes]);
  }

  // F265, one direction that passes F2650 "Twice" at indices 13 and 28: east
  // along a road, then once round a 1 km circle and back through it.
  {
    LatLng p(double n, double e) => _at(1.30, 103.75, n, e);
    final codes = <String>[
      for (var k = 0; k < 13; k++)
        b.stop('F265${k + 10}', p(0, k * 400.0), 'Approach $k'),
    ];
    final twice = b.stop('F2650', p(0, 5200), 'Twice');
    codes.add(twice); // 13
    for (var i = 1; i <= 14; i++) {
      final a = -math.pi / 2 + i * 2 * math.pi / 15;
      codes.add(
        b.stop(
          'F265${i + 30}',
          p(1000 + 1000 * math.sin(a), 5200 + 1000 * math.cos(a)),
          'Circle $i',
        ),
      ); // 14..27
    }
    codes.add(twice); // 28
    for (var j = 29; j <= 34; j++) {
      codes.add(
        b.stop('F265${j + 30}', p(-300, 5200 + (j - 28) * 400.0), 'Onward $j'),
      );
    }
    b.service('F265', [codes]);
  }

  // F647, two directions. Direction 1 lists F6479 "Double" twice in a row,
  // at indices 22 and 23.
  {
    LatLng p(double n, double e) => _at(1.33, 103.62, n, e);
    final dir0 = [
      for (var k = 0; k < 30; k++)
        b.stop('F647${k + 10}', p(0, k * 300.0), 'Westbound side $k'),
    ];
    final dir1 = <String>[];
    for (var k = 0; k < 30; k++) {
      if (k == 23) {
        dir1.add(dir1.last); // the same stop again
      } else if (k == 22) {
        dir1.add(b.stop('F6479', p(500, (29 - k) * 300.0), 'Double'));
      } else {
        dir1.add(
          b.stop(
            'F647${k + 50}',
            p(500, (29 - k) * 300.0),
            'Eastbound side $k',
          ),
        );
      }
    }
    b.service('F647', [dir0, dir1]);
  }

  // F65, two ordinary directions on opposite sides of a road, 300 m apart.
  {
    LatLng p(double n, double e) => _at(1.38, 103.80, n, e);
    final dir0 = [
      for (var k = 0; k < 25; k++)
        b.stop('F65${k + 10}', p(0, k * 350.0), 'Outbound $k'),
    ];
    final dir1 = [
      for (var k = 0; k < 25; k++)
        b.stop('F65${k + 50}', p(300, (24 - k) * 350.0), 'Inbound $k'),
    ];
    b.service('F65', [dir0, dir1]);
  }

  // F160 crosses the border: F9999 lies north of the app's GPS box
  // (SgBounds) but inside the transport-data bounds.
  {
    final across = b.stop(
      'F9999',
      const LatLng(1.4955, 103.765),
      'Across the border',
      road: 'Fake Jln',
    );
    final south = [
      for (var k = 0; k < 4; k++)
        b.stop(
          'F160${k + 10}',
          _at(1.44, 103.77, k * 400.0, 0),
          'Border road $k',
        ),
    ];
    final north = [
      for (var k = 0; k < 4; k++)
        b.stop(
          'F160${k + 50}',
          _at(1.44, 103.772, (3 - k) * 400.0, 0),
          'Border road back $k',
        ),
    ];
    b.service('F160', [
      [...south, across],
      [across, ...north],
    ]);
  }
  return b;
}();

/// Stops of the planner network, as `stops.min.json` would hold them.
Map<String, Object?> get syntheticStopsJson => _network.stops;

/// Services of the planner network, as `services.min.json` would hold them.
Map<String, Object?> get syntheticServicesJson => _network.services;

/// The two files as response bodies.
String get syntheticStopsBody => jsonEncode(_network.stops);
String get syntheticServicesBody => jsonEncode(_network.services);

// ---------------------------------------------------------------------------
// Ride-line network (ride_geometry_test.dart, busrouter_routes_test.dart):
// six services with route polylines, each built for one matcher case.

final _Builder _geometry = () {
  final b = _Builder();

  // A line through [stops] with a bend between each pair: a vertex at the
  // midpoint, moved [bend] metres north.
  List<LatLng> bent(List<LatLng> stops, {double bend = 30}) => [
    for (var i = 0; i < stops.length; i++) ...[
      if (i > 0)
        LatLng(
          (stops[i - 1].latitude + stops[i].latitude) / 2 +
              bend / _metresPerDegree,
          (stops[i - 1].longitude + stops[i].longitude) / 2,
        ),
      stops[i],
    ],
  ];

  // F10, two open directions.
  // Direction 0: 15 stops 400 m apart, the line bent between them; the ride
  // 3 → 12 is drawn.
  // Direction 1: a U-shaped open line from F1051 to F1050 (the stops are
  // 424 m apart, the line about 7.6 km long). The ride F1050 → F1051 can only
  // be matched through the artificial join from the line's end to its start,
  // so it is never drawn (the line is not closed, so it is never doubled).
  {
    LatLng p(double n, double e) => _at(1.29, 103.80, n, e);
    final dir0 = [
      for (var k = 0; k < 15; k++)
        b.stop('F10${k + 10}', p(0, k * 400.0), 'Ten east $k'),
    ];
    final s0 = b.stop('F1050', p(900, 0), 'Ten west end');
    final s1 = b.stop('F1051', p(600, 300), 'Ten west start');
    final s2 = b.stop('F1052', p(600, 2000), 'Ten west middle');
    b.service('F10', [
      dir0,
      [s0, s1, s2],
    ]);
    b.line('F10', [
      bent([for (final c in dir0) b.pos(c)]),
      [p(600, 300), p(600, 3000), p(1500, 3000), p(1500, 0), p(900, 0)],
    ]);
  }

  // F4, a closed loop (route and line start and end at F0400): the ride
  // 0 → 1 is drawn on the line as given.
  {
    LatLng p(double n, double e) => _at(1.36, 103.86, n, e);
    final corners = [
      for (var k = 0; k < 4; k++) p(0, k * 500.0),
      for (var k = 0; k < 4; k++) p(1000, (3 - k) * 500.0),
    ];
    final codes = [
      for (var k = 0; k < corners.length; k++)
        b.stop(
          'F04${k + 10}',
          corners[k],
          k == 0 ? 'Loop terminal' : 'Loop $k',
        ),
    ];
    b.service('F4', [
      [...codes, codes.first],
    ]);
    b.line('F4', [
      bent([...corners, corners.first]),
    ]);
  }

  // F115, a closed loop whose line starts halfway between stops 0 and 1, so
  // the ride 0 → 1 runs across the line's start: drawn only on the doubled
  // line.
  {
    LatLng p(double n, double e) => _at(1.31, 103.90, n, e);
    final ring = [
      for (var k = 0; k < 4; k++) p(0, k * 400.0),
      for (var k = 0; k < 4; k++) p(800, (3 - k) * 400.0),
    ];
    final codes = [
      for (var k = 0; k < ring.length; k++)
        b.stop('F115${k + 10}', ring[k], 'Ring $k'),
    ];
    b.service('F115', [
      [...codes, codes.first],
    ]);
    final start = p(0, 200); // halfway between stops 0 and 1
    b.line('F115', [
      [start, ...ring.skip(1), ring.first, start],
    ]);
  }

  // F46, two directions; direction 1's line is stored backwards (last stop
  // first).
  {
    LatLng p(double n, double e) => _at(1.34, 103.70, n, e);
    final dir0 = [
      for (var k = 0; k < 5; k++)
        b.stop('F46${k + 10}', p(0, k * 300.0), 'Forty-six out $k'),
    ];
    final dir1 = [
      for (var k = 0; k < 5; k++)
        b.stop('F46${k + 50}', p(200, (4 - k) * 300.0), 'Forty-six back $k'),
    ];
    b.service('F46', [dir0, dir1]);
    b.line('F46', [
      bent([for (final c in dir0) b.pos(c)]),
      bent([for (final c in dir1) b.pos(c)]).reversed.toList(),
    ]);
  }

  // F11, one open direction that serves F1199 "Twice" at indices 6 and 17:
  // east to it, once round a loop to the north and back to it, then south.
  // The rides 6 → 8 and 17 → 19 board at the same stop and are drawn on
  // their own passes, with different lengths.
  {
    LatLng p(double n, double e) => _at(1.395, 103.90, n, e);
    final twice = p(0, 2400);
    final positions = <LatLng>[
      for (var k = 0; k < 6; k++) p(0, k * 400.0), // 0..5
      twice, // 6
      for (var k = 1; k <= 5; k++) p(k * 500.0, 2400), // 7..11 north
      p(2500, 2900), // 12
      for (var k = 1; k <= 4; k++) p(2500 - k * 500.0, 2900), // 13..16 back
      twice, // 17
      for (var k = 1; k <= 3; k++) p(-k * 150.0, 2400), // 18..20 south
    ];
    final codes = <String>[];
    for (var i = 0; i < positions.length; i++) {
      codes.add(
        i == 17
            ? codes[6]
            : b.stop(
                i == 6 ? 'F1199' : 'F11${i + 10}',
                positions[i],
                i == 6 ? 'Twice' : 'Eleven $i',
              ),
      );
    }
    b.service('F11', [codes]);
    b.line('F11', [positions]);
  }

  // F2B, one direction whose line lies 500 m north of every stop: the line
  // does not fit the ride.
  {
    LatLng p(double n, double e) => _at(1.32, 103.98, n, e);
    final codes = [
      for (var k = 0; k < 4; k++)
        b.stop('F2B${k + 10}', p(0, k * 300.0), 'Off line $k'),
    ];
    b.service('F2B', [codes]);
    b.line('F2B', [
      [for (var k = 0; k < 4; k++) p(500, k * 300.0)],
    ]);
  }
  return b;
}();

/// Stops, services and route lines of the ride-line network, as busrouter's
/// files would hold them.
Map<String, Object?> get geometryStopsJson => _geometry.stops;
Map<String, Object?> get geometryServicesJson => _geometry.services;
Map<String, Object?> get geometryRoutesJson => _geometry.routes;
String get geometryRoutesBody => jsonEncode(_geometry.routes);
