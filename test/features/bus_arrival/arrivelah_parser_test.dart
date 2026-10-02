// ArriveLah DTO parsing (guide v2.1 §10, §18). The fixtures are real
// responses captured once on 2026-10-02 (test/fixtures/arrivelah/).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/core/errors/app_failure.dart';
import 'package:sg_smart_commute/features/bus_arrival/data/arrivelah_parser.dart';
import 'package:sg_smart_commute/features/bus_arrival/domain/bus_arrival.dart';

Object? fixture(String name) =>
    jsonDecode(File('test/fixtures/arrivelah/$name').readAsStringSync());

Map<String, dynamic> bus({
  Object? time = '2026-10-02T11:05:00+08:00',
  Object? load = 'SEA',
  Object? feature = 'WAB',
  Object? type = 'SD',
  Object? monitored = 1,
  Object? visit = 1,
}) => {
  'time': time,
  'duration_ms': 123,
  'lat': 1.3,
  'lng': 103.8,
  'load': load,
  'feature': feature,
  'type': type,
  'visit_number': visit,
  'origin_code': '1',
  'destination_code': '2',
  'monitored': monitored,
};

StopArrivals one(Map<String, dynamic>? next, {Object? no = '10'}) =>
    parseArriveLah({
      'services': [
        {'no': no, 'next': next, 'subsequent': null, 'next2': null},
      ],
    }, '03019');

void main() {
  group('real fixture: stop 03019 (OUE Bayfront)', () {
    final stop = parseArriveLah(fixture('stop_03019.json'), '03019');
    ServiceArrivals svc(String no) =>
        stop.services.singleWhere((s) => s.serviceNo == no);

    test('every listed service, in the provider order', () {
      expect(stop.services.map((s) => s.serviceNo), [
        '10',
        '100',
        '107',
        '130',
        '131',
        '167',
        '196',
        '196A',
        '57',
        '70',
      ]);
    });

    test('next, next2, next3 read; the legacy "subsequent" copy skipped', () {
      final ten = svc('10');
      expect(ten.arrivals, hasLength(3));
      expect(ten.arrivals.map((a) => a.estimatedArrival), [
        DateTime.utc(2026, 10, 2, 3, 0, 57), // 11:00:57+08:00
        DateTime.utc(2026, 10, 2, 3, 19, 45),
        DateTime.utc(2026, 10, 2, 3, 29, 4),
      ]);
      final a = ten.arrivals.first;
      expect(a.estimatedArrival!.isUtc, isTrue);
      expect(a.serviceNo, '10');
      expect(a.busStopCode, '03019');
      expect(a.load, BusLoad.seatsAvailable);
      expect(a.wheelchairAccessible, isTrue);
      expect(a.type, BusType.doubleDeck);
      expect(a.monitored, isTrue);
      expect(a.visitNumber, 1);
      expect(a.source, 'ArriveLah');
    });

    test('partial entries: a null slot is simply absent', () {
      expect(svc('167').arrivals, hasLength(2)); // next3: null
      expect(svc('196A').arrivals, hasLength(1)); // only next
      expect(svc('100').arrivals.first.load, BusLoad.standingAvailable);
      expect(svc('100').arrivals.first.type, BusType.singleDeck);
    });
  });

  test('real fixture: loop interchange 75009 keeps visit numbers and '
      'schedule-based (monitored 0) estimates', () {
    final stop = parseArriveLah(fixture('stop_75009_loop.json'), '75009');
    final loop = stop.services.singleWhere((s) => s.serviceNo == '291');
    expect(loop.arrivals.map((a) => a.visitNumber), [2, 2, 1]);
    expect(loop.arrivals.map((a) => a.monitored), [true, true, false]);
  });

  group('failure and empty bodies (all observed with HTTP 200)', () {
    test('unknown stop → empty service list, not a failure', () {
      final stop = parseArriveLah(fixture('stop_99999_empty.json'), '99999');
      expect(stop.services, isEmpty);
    });

    test('{"error": …} → BusArrivalUnavailable', () {
      expect(
        () => parseArriveLah(fixture('error_body.json'), 'abc'),
        throwsA(isA<BusArrivalUnavailable>()),
      );
      expect(
        () => parseArriveLah({'error': 'Unable to retrieve'}, '1'),
        throwsA(isA<BusArrivalUnavailable>()),
      );
    });

    test(
      'no services list (e.g. the instruction page) → InvalidApiResponse',
      () {
        expect(
          () => parseArriveLah(fixture('no_id_instruction.json'), ''),
          throwsA(isA<InvalidApiResponse>()),
        );
        expect(
          () => parseArriveLah([1, 2], '1'),
          throwsA(isA<InvalidApiResponse>()),
        );
        expect(
          () => parseArriveLah({'services': 'x'}, '1'),
          throwsA(isA<InvalidApiResponse>()),
        );
      },
    );

    test('malformed service entries are skipped; all malformed → invalid', () {
      final stop = parseArriveLah({
        'services': [
          {'no': '', 'next': bus()},
          {'next': bus()},
          'x',
          {'no': ' 65 ', 'next': bus()},
        ],
      }, '1');
      expect(stop.services.single.serviceNo, '65');
      expect(
        () => parseArriveLah({
          'services': [
            {'no': 7},
            null,
          ],
        }, '1'),
        throwsA(isA<InvalidApiResponse>()),
      );
    });

    test('a slot that is not an object is skipped', () {
      final stop = parseArriveLah({
        'services': [
          {'no': '10', 'next': 'soon', 'next2': bus(), 'next3': 5},
        ],
      }, '1');
      expect(stop.services.single.arrivals, hasLength(1));
    });
  });

  group('timestamps', () {
    test('parsed with their own offset and stored in UTC', () {
      expect(
        one(bus(time: '2026-10-02T23:59:30+08:00'))
            .services
            .single
            .arrivals
            .single
            .estimatedArrival,
        DateTime.utc(2026, 10, 2, 15, 59, 30),
      );
      expect(
        one(bus(time: '2026-10-02T03:00:00Z'))
            .services
            .single
            .arrivals
            .single
            .estimatedArrival,
        DateTime.utc(2026, 10, 2, 3),
      );
    });

    for (final bad in <Object?>[
      null,
      '',
      'soon',
      '2026-13-45T25:00:00+08:00', // DateTime.parse alone rolls this over
      '2026-02-30T11:05:00+08:00',
      '2026-10-02T11:61:00+08:00',
      '2026-10-02T11:05:00+25:00',
      '2026-10-02T11:05:00', // no offset: would be read as device-local
      1790910067492,
    ]) {
      test('missing or invalid time ${jsonEncode(bad)} → no ETA (null), '
          'never a made-up one', () {
        final a = one(bus(time: bad)).services.single.arrivals.single;
        expect(a.estimatedArrival, isNull);
      });
    }
  });

  group('optional fields never fail the arrival', () {
    test('unknown codes → null; the ETA is kept', () {
      final a = one(
        bus(load: 'FULL', feature: 'RAMP', type: 'TRAM', monitored: 'x'),
      ).services.single.arrivals.single;
      expect(a.estimatedArrival, isNotNull);
      expect(a.load, isNull);
      expect(a.wheelchairAccessible, isNull);
      expect(a.type, isNull);
      expect(a.monitored, isNull);
    });

    test('missing fields → null; empty feature → not marked accessible', () {
      final a = one({'time': '2026-10-02T11:05:00+08:00', 'feature': ''})
          .services
          .single
          .arrivals
          .single;
      expect(a.estimatedArrival, isNotNull);
      expect(a.wheelchairAccessible, isFalse);
      expect(a.load, isNull);
      expect(a.type, isNull);
      expect(a.visitNumber, isNull);
    });

    test('all load and type codes; monitored 0/1 as int or string', () {
      for (final (code, load) in [
        ('SEA', BusLoad.seatsAvailable),
        ('SDA', BusLoad.standingAvailable),
        ('LSD', BusLoad.limitedStanding),
      ]) {
        expect(one(bus(load: code)).services.single.arrivals.single.load, load);
      }
      for (final (code, type) in [
        ('SD', BusType.singleDeck),
        ('DD', BusType.doubleDeck),
        ('BD', BusType.bendy),
      ]) {
        expect(one(bus(type: code)).services.single.arrivals.single.type, type);
      }
      expect(
        one(bus(monitored: 0)).services.single.arrivals.single.monitored,
        isFalse,
      );
      expect(
        one(bus(monitored: '1')).services.single.arrivals.single.monitored,
        isTrue,
      );
      expect(
        one(bus(visit: '2')).services.single.arrivals.single.visitNumber,
        2,
      );
    });
  });
}
