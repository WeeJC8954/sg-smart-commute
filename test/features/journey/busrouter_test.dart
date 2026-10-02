// busrouter parsing, the repository, and the planner on real routes. The
// fixtures in test/fixtures/busrouter/ are unmodified subsets of the live
// files (downloaded 2026-10-01): services 4 (loop), 184 (one direction), 265
// (stop 54009 twice), 647 (43589 twice in a row), 65 and 160, every stop they
// use, and 46239 Larkin Ter (across the Causeway).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sg_smart_commute/core/config/app_config.dart';
import 'package:sg_smart_commute/core/errors/app_failure.dart';
import 'package:sg_smart_commute/core/http/json_http_client.dart';
import 'package:sg_smart_commute/features/journey/data/busrouter_parser.dart';
import 'package:sg_smart_commute/features/journey/data/busrouter_repository.dart';
import 'package:sg_smart_commute/features/journey/domain/bus_network.dart';
import 'package:sg_smart_commute/features/journey/domain/direct_bus_planner.dart';

final String stopsBody = File('test/fixtures/busrouter/stops.subset.json')
    .readAsStringSync();
final String servicesBody = File('test/fixtures/busrouter/services.subset.json')
    .readAsStringSync();

BusNetwork realNetwork() {
  final stops = parseBusrouterStops(jsonDecode(stopsBody));
  return BusNetwork(
    stops: stops,
    services: parseBusrouterServices(jsonDecode(servicesBody), stops),
  );
}

Matcher unavailable() => throwsA(isA<StaticDataUnavailable>());

void main() {
  group('stops: [longitude, latitude, name, road]', () {
    test('longitude first in the source, latitude first in the model', () {
      final stops = parseBusrouterStops({
        '01012': [103.85405, 1.29685, 'Hotel Grand Pacific', 'Victoria St'],
      });
      final s = stops['01012']!;
      expect(s.position.latitude, 1.29685);
      expect(s.position.longitude, 103.85405);
      expect(s.name, 'Hotel Grand Pacific');
      expect(s.road, 'Victoria St');
      expect(s.code, '01012'); // leading zero kept
    });

    test('real fixture: 75009 Tampines Int parses with the right order', () {
      final stops = parseBusrouterStops(jsonDecode(stopsBody));
      final t = stops['75009']!;
      expect(t.name, 'Tampines Int');
      expect(t.position.latitude, closeTo(1.354, 0.01));
      expect(t.position.longitude, closeTo(103.943, 0.01));
    });

    test(
      '46239 Larkin Ter (outside the app GPS box) is valid transport data',
      () {
        final stops = parseBusrouterStops(jsonDecode(stopsBody));
        expect(stops['46239']!.position.latitude, closeTo(1.4955, 0.0001));
      },
    );

    test('a swapped lat/lng entry is rejected by the range check', () {
      final good = {
        for (var i = 0; i < 40; i++) 'A$i': [103.8, 1.3, 'Stop $i', 'Road'],
      };
      final stops = parseBusrouterStops({
        ...good,
        'SWAP': [1.3, 103.8, 'Swapped', 'Road'],
      });
      expect(stops.containsKey('SWAP'), isFalse);
      expect(stops, hasLength(40));
    });

    test('malformed: wrong top level, empty, or > 5 % invalid → '
        'StaticDataUnavailable', () {
      expect(() => parseBusrouterStops([1, 2]), unavailable());
      expect(() => parseBusrouterStops(<String, dynamic>{}), unavailable());
      expect(() => parseBusrouterStops('x'), unavailable());
      expect(
        () => parseBusrouterStops({
          'A': [103.8, 1.3, 'Ok', 'Road'],
          'B': {'lng': 103.8},
        }),
        unavailable(),
      ); // 50 % invalid
      expect(
        () => parseBusrouterStops({
          'A': ['103.8', '1.3', 'Strings', 'Road'],
        }),
        unavailable(),
      );
    });

    test('invalid-share boundary: exactly 5 % passes, just above fails', () {
      expect(BusrouterValidation.maxInvalidShare, 0.05);
      Map<String, dynamic> withOneBad(int good) => {
        for (var i = 0; i < good; i++) 'A$i': [103.8, 1.3, 'Stop $i', 'Road'],
        'BAD': {'lng': 103.8},
      };
      expect(parseBusrouterStops(withOneBad(19)), hasLength(19)); // 1/20 = 5 %
      expect(() => parseBusrouterStops(withOneBad(18)), unavailable()); // 5.3 %
    });
  });

  group('services: {name, routes: [[codes], [codes]?]}', () {
    test('real fixture: directions and order preserved', () {
      final net = realNetwork();
      expect(net.services.keys, containsAll(['4', '184', '265', '647', '65']));
      expect(net.services['65']!.directions, hasLength(2));
      expect(net.services['4']!.directions, hasLength(1)); // loop
      expect(net.services['184']!.directions, hasLength(1)); // one way
      final loop = net.services['4']!.directions.single;
      expect(loop.first, '75009');
      expect(loop.last, '75009');
      final r265 = net.services['265']!.directions.single;
      expect(
        [
          for (var i = 0; i < r265.length; i++)
            if (r265[i] == '54009') i,
        ],
        [13, 28],
      );
      final r647 = net.services['647']!.directions[1];
      expect(
        [
          for (var i = 0; i < r647.length; i++)
            if (r647[i] == '43589') i,
        ],
        [22, 23],
      );
    });

    test('unknown stop codes are removed; too-short routes dropped', () {
      final stops = parseBusrouterStops({
        'A': [103.8, 1.3, 'A', 'R'],
        'B': [103.81, 1.3, 'B', 'R'],
        'C': [103.82, 1.3, 'C', 'R'],
      });
      final services = parseBusrouterServices({
        for (var i = 0; i < 30; i++)
          'S$i': {
            'name': 'S',
            'routes': [
              ['A', 'B'],
            ],
          },
        'X': {
          'name': 'X',
          'routes': [
            ['A', 'ZZZ', 'C'],
            ['ZZZ', 'B'],
          ],
        },
      }, stops);
      expect(services['X']!.directions, [
        ['A', 'C'],
      ]);
    });

    test('malformed services → StaticDataUnavailable', () {
      final stops = parseBusrouterStops({
        'A': [103.8, 1.3, 'A', 'R'],
        'B': [103.81, 1.3, 'B', 'R'],
      });
      expect(() => parseBusrouterServices([1], stops), unavailable());
      expect(
        () => parseBusrouterServices({
          '1': {'name': 'x', 'routes': 'nope'},
        }, stops),
        unavailable(),
      );
      expect(
        () => parseBusrouterServices({
          '1': {
            'routes': [
              ['A', 'B'],
            ],
          },
        }, stops),
        unavailable(),
      ); // no name
      expect(
        () => parseBusrouterServices({
          '1': {
            'name': 'x',
            'routes': [
              [1, 2],
            ],
          },
        }, stops),
        unavailable(),
      );
    });
  });

  group('planner on real busrouter routes (10 m radius: exact stops only)', () {
    const exact = PlannerConfig(
      stopRadiusMeters: 10,
      widenedStopRadiusMeters: 10,
    );
    late BusNetwork net;
    setUp(() => net = realNetwork());

    BusOption only(String service, JourneyPlan plan) =>
        (plan as DirectBusOptions).options.firstWhere(
          (o) => o.service.number == service,
        );

    test('loop 4: mid-loop to Tampines Int boards forward to the end', () {
      final r = net.services['4']!.directions.single;
      final opt = only(
        '4',
        planDirectBus(
          net,
          net.stops[r[5]]!.position,
          net.stops['75009']!.position,
          config: exact,
        ),
      );
      expect(opt.board.code, r[5]);
      expect(opt.alight.code, '75009');
      expect(opt.stops, r.length - 1 - 5);
      expect(opt.isLoop, isTrue);
      expect(opt.towardName, 'Tampines Int');
    });

    test('loop 4: an opposite-side stop on the return leg gives the shorter '
        'ride, and is chosen', () {
      // 76231 "Opp Blk 390 Tampines Ave 7" (index 5) and 76239 "Blk 390
      // Tampines Ave 7" (index 22) are 29.1 m apart. With both in range,
      // riding from 76239 back to Tampines Int (5 stops) beats 22 stops.
      final opt = only(
        '4',
        planDirectBus(
          net,
          net.stops['76231']!.position,
          net.stops['75009']!.position,
          config: const PlannerConfig(
            stopRadiusMeters: 40,
            widenedStopRadiusMeters: 40,
          ),
        ),
      );
      expect(opt.board.code, '76239');
      expect(opt.stops, 5);
    });

    test(
      'loop 4: from Tampines Int, the first occurrence (index 0) is used',
      () {
        final r = net.services['4']!.directions.single;
        final opt = only(
          '4',
          planDirectBus(
            net,
            net.stops['75009']!.position,
            net.stops[r[5]]!.position,
            config: exact,
          ),
        );
        expect(opt.stops, 5);
      },
    );

    test('one-direction 184: forward matches, reverse does not', () {
      final r = net.services['184']!.directions.single;
      final a = net.stops[r[3]]!.position;
      final b = net.stops[r[40]]!.position;
      expect(only('184', planDirectBus(net, a, b, config: exact)).stops, 37);
      final reverse = planDirectBus(net, b, a, config: exact);
      expect(
        reverse is DirectBusOptions &&
            reverse.options.any((o) => o.service.number == '184'),
        isFalse,
      );
    });

    test(
      '265: 54009 appears at 13 and 28; the shortest valid segment wins',
      () {
        final r = net.services['265']!.directions.single;
        final from = net.stops['54009']!.position;
        // To index 30: from 13 is 17 stops, from 28 is 2 → 2.
        expect(
          only(
            '265',
            planDirectBus(net, from, net.stops[r[30]]!.position, config: exact),
          ).stops,
          2,
        );
        // To index 20: only the occurrence at 13 precedes it → 7.
        expect(
          only(
            '265',
            planDirectBus(net, from, net.stops[r[20]]!.position, config: exact),
          ).stops,
          7,
        );
      },
    );

    test('647: 43589 twice in a row (22, 23); the first after o counts', () {
      final r = net.services['647']!.directions[1];
      final opt = only(
        '647',
        planDirectBus(
          net,
          net.stops[r[10]]!.position,
          net.stops['43589']!.position,
          config: exact,
        ),
      );
      expect(opt.direction, 1);
      expect(opt.stops, 12); // index 10 → 22, not 23
    });

    test('65: two directions; the direction where o precedes d is used', () {
      final dir0 = net.services['65']!.directions[0];
      final opt = only(
        '65',
        planDirectBus(
          net,
          net.stops[dir0[5]]!.position,
          net.stops[dir0[20]]!.position,
          config: exact,
        ),
      );
      expect(opt.direction, 0);
      expect(opt.stops, 15);
      expect(opt.towardName, net.stops[dir0.last]!.name);
    });
  });

  group('BusrouterRepository', () {
    late int stopsCalls;
    late int servicesCalls;

    BusrouterRepository repo(
      FutureOr<http.Response> Function(String file) respond,
    ) => BusrouterRepository(
      JsonHttpClient(
        MockClient((r) async {
          final file = r.url.pathSegments.last;
          if (file == 'stops.min.json') stopsCalls++;
          if (file == 'services.min.json') servicesCalls++;
          return respond(file);
        }),
        timeout: const Duration(milliseconds: 200),
        delay: (_) async {},
      ),
    );

    http.Response ok(String file) => http.Response.bytes(
      utf8.encode(file == 'stops.min.json' ? stopsBody : servicesBody),
      200,
    );

    setUp(() {
      stopsCalls = 0;
      servicesCalls = 0;
    });

    test('nothing is fetched until load(); then both files, once', () async {
      final r = repo(ok);
      expect(stopsCalls + servicesCalls, 0);
      final net = await r.load();
      expect(net.stops, hasLength(367));
      expect(net.services, hasLength(6));
      expect((stopsCalls, servicesCalls), (1, 1));
    });

    test('session cache: later loads reuse the first result', () async {
      final r = repo(ok);
      final a = await r.load();
      final b = await r.load();
      expect(identical(a, b), isTrue);
      expect((stopsCalls, servicesCalls), (1, 1));
    });

    test('concurrent loads share one download', () async {
      final r = repo(ok);
      final results = await Future.wait([r.load(), r.load(), r.load()]);
      expect(identical(results[0], results[2]), isTrue);
      expect((stopsCalls, servicesCalls), (1, 1));
    });

    test(
      'HTTP failure → StaticDataUnavailable; a later load retries',
      () async {
        var fail = true;
        final r = repo((file) => fail ? http.Response('down', 404) : ok(file));
        await expectLater(r.load(), unavailable());
        fail = false;
        expect((await r.load()).services, hasLength(6));
        expect(stopsCalls, 2);
      },
    );

    test('network failure and timeout → StaticDataUnavailable', () async {
      final offline = repo((_) => throw http.ClientException('offline'));
      await expectLater(offline.load(), unavailable());
      final slow = repo((file) async {
        await Future<void>.delayed(const Duration(seconds: 1));
        return ok(file);
      });
      await expectLater(slow.load(), unavailable());
    });

    test('malformed JSON or schema → StaticDataUnavailable', () async {
      await expectLater(
        repo((_) => http.Response('<html>', 200)).load(),
        unavailable(),
      );
      await expectLater(
        repo(
          (file) => file == 'stops.min.json'
              ? http.Response('[1,2,3]', 200)
              : ok(file),
        ).load(),
        unavailable(),
      );
      await expectLater(
        repo(
          (file) => file == 'services.min.json'
              ? http.Response('{"1": {"name": 2}}', 200)
              : ok(file),
        ).load(),
        unavailable(),
      );
    });
  });
}
