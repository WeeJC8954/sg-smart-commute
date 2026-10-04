// P2-M1: the pure journey → map-scene transformation. The plans come from the
// real planner over the fake bus network (integration_test/fakes/), so the
// stops shown are exactly the ones the journey card suggests.
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/core/geo/geo.dart';
import 'package:sg_smart_commute/features/journey/domain/bus_network.dart';
import 'package:sg_smart_commute/features/journey/domain/direct_bus_planner.dart';
import 'package:sg_smart_commute/features/journey/domain/mrt.dart';
import 'package:sg_smart_commute/features/journey/domain/walking.dart';
import 'package:sg_smart_commute/features/map/domain/map_scene.dart';
import 'package:sg_smart_commute/features/map/domain/ride_geometry.dart';

import '../../../integration_test/fakes/fake_bus_network.dart';
import '../../../integration_test/fakes/fake_place_search_repository.dart';

const bishan = LatLng(1.3508, 103.8485);

MapScene sceneTo(
  LatLng destination, {
  JourneyPlan? plan,
  int selectedIndex = 0,
  ({MrtSuggestion? nearOrigin, MrtSuggestion? nearDestination})? mrt,
  Map<String, BusStop>? stops,
}) => buildMapScene(
  origin: bishan,
  originLabel: 'Current location',
  destination: destination,
  destinationLabel: 'Destination',
  plan: plan,
  selectedIndex: selectedIndex,
  mrt: mrt,
  stops: stops,
);

List<MapMarkerKind> kinds(MapScene s) => [for (final m in s.markers) m.kind];

void main() {
  final network = fakeBusNetwork();

  test('a direct bus: origin, boarding, alighting, destination, in order, '
      'from the suggested option', () {
    final plan = planDirectBus(network, bishan, vivoCity.position);
    expect(plan, isA<DirectBusOptions>());
    final suggested = (plan as DirectBusOptions).options.first;

    final scene = sceneTo(vivoCity.position, plan: plan);

    expect(kinds(scene), [
      MapMarkerKind.origin,
      MapMarkerKind.boarding,
      MapMarkerKind.alighting,
      MapMarkerKind.destination,
    ]);
    expect(scene.serviceNumber, 'F20');
    final board = scene.markers[1], alight = scene.markers[2];
    expect(board.position, same(suggested.board.position));
    expect(board.label, 'Opp Bishan Stn (fake) (BSH2)');
    expect(alight.position, same(suggested.alight.position));
    expect(alight.label, 'VivoCity (fake) (VIV1)');
    expect(scene.markers.first.position, bishan);
    expect(scene.markers.last.position, vivoCity.position);
  });

  test('every other answer, and no answer yet, marks the two ends only', () {
    final plans = <JourneyPlan?>[
      null, // still being found, or failed
      WalkOnly(WalkEstimate.between(bishan, bishan)),
      planDirectBus(network, tampinesHub.position, ionOrchard.position),
      const NoNearbyStops(JourneyEnd.origin, radiusMeters: 800),
      const DirectBusOptions([], radiusMeters: 400),
    ];
    expect(plans[2], isA<NoDirectBus>());
    for (final plan in plans) {
      final scene = sceneTo(ionOrchard.position, plan: plan);
      expect(kinds(scene), [
        MapMarkerKind.origin,
        MapMarkerKind.destination,
      ], reason: '$plan');
      expect(scene.serviceNumber, isNull);
    }
  });

  test('bounds hold every marker', () {
    final plan = planDirectBus(network, bishan, vivoCity.position);
    final scene = sceneTo(vivoCity.position, plan: plan);
    final b = scene.bounds;
    for (final m in scene.markers) {
      expect(
        m.position.latitude,
        inInclusiveRange(b.southWest.latitude, b.northEast.latitude),
      );
      expect(
        m.position.longitude,
        inInclusiveRange(b.southWest.longitude, b.northEast.longitude),
      );
    }
    // Tight: each edge is some marker's coordinate.
    final lats = scene.markers.map((m) => m.position.latitude);
    final lngs = scene.markers.map((m) => m.position.longitude);
    expect(b.southWest.latitude, lats.reduce((a, c) => a < c ? a : c));
    expect(b.northEast.latitude, lats.reduce((a, c) => a > c ? a : c));
    expect(b.southWest.longitude, lngs.reduce((a, c) => a < c ? a : c));
    expect(b.northEast.longitude, lngs.reduce((a, c) => a > c ? a : c));
  });

  test(
    'the summary names the ends, and the bus and stops when there is one',
    () {
      final plan = planDirectBus(network, bishan, vivoCity.position);
      expect(
        sceneTo(vivoCity.position, plan: plan).summary,
        'Map of the suggested journey: from Current location, bus F20 from '
        'Opp Bishan Stn (fake) (BSH2) to VivoCity (fake) (VIV1), to '
        'Destination. Walks are drawn as straight lines, estimates only. '
        'The journey details are listed above.',
      );
      expect(
        sceneTo(vivoCity.position).summary,
        'Map of the suggested journey: from Current location, to Destination. '
        'The journey details are listed above.',
      );
    },
  );

  test('equal inputs give equal scenes; a new journey does not', () {
    final plan = planDirectBus(network, bishan, vivoCity.position);
    final a = sceneTo(vivoCity.position, plan: plan);
    final b = sceneTo(
      vivoCity.position,
      plan: planDirectBus(network, bishan, vivoCity.position),
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(sceneTo(vivoCity.position))); // stops not known yet
    expect(a, isNot(sceneTo(ionOrchard.position)));
  });

  group('the ride (P2-M2)', () {
    final stops = network.stops;
    final plan = planDirectBus(network, bishan, vivoCity.position);
    final option = (plan as DirectBusOptions).options.first;

    test('a direct bus gives the ride: the suggested stops, in order, '
        'boarding to alighting', () {
      final ride = sceneTo(vivoCity.position, plan: plan, stops: stops).ride!;
      final codes = network.services['F20']!.directions[0];
      expect(ride.service, 'F20');
      expect(ride.boardIndex, option.boardIndex);
      expect(ride.sourceDirection, 0);
      expect(ride.stops, [
        for (final c in codes.sublist(
          option.boardIndex,
          option.boardIndex + option.stops + 1,
        ))
          stops[c]!.position,
      ]);
      expect(ride.leadingStops, isEmpty, reason: 'a unique ride needs none');
    });

    test('no ride without the stops, or for any other answer', () {
      expect(sceneTo(vivoCity.position, plan: plan).ride, isNull);
      final others = <JourneyPlan?>[
        null,
        WalkOnly(WalkEstimate.between(bishan, bishan)),
        planDirectBus(network, tampinesHub.position, ionOrchard.position),
        const NoNearbyStops(JourneyEnd.origin, radiusMeters: 800),
        const DirectBusOptions([], radiusMeters: 400),
      ];
      for (final other in others) {
        expect(
          sceneTo(ionOrchard.position, plan: other, stops: stops).ride,
          isNull,
          reason: '$other',
        );
      }
    });

    test('bounds hold every ride stop, not only the markers', () {
      BusStop s(String code, double lat, double lng) => BusStop(
        code: code,
        position: LatLng(lat, lng),
        name: code,
        road: 'Fake Rd',
      );
      final detour = BusNetwork(
        stops: {
          'A': s('A', 1.3510, 103.8490),
          'B': s('B', 1.4200, 103.9000), // north-east of every marker
          'C': s('C', 1.2645, 103.8226),
        },
        services: const {
          'R1': BusService(
            number: 'R1',
            name: 'R1',
            directions: [
              ['A', 'B', 'C'],
            ],
          ),
        },
      );
      final detourPlan = planDirectBus(detour, bishan, vivoCity.position);
      expect(detourPlan, isA<DirectBusOptions>());
      final scene = sceneTo(
        vivoCity.position,
        plan: detourPlan,
        stops: detour.stops,
      );
      expect(scene.ride, isNotNull);
      final b = scene.bounds;
      for (final p in [
        ...scene.ride!.stops,
        ...scene.markers.map((m) => m.position),
      ]) {
        expect(
          p.latitude,
          inInclusiveRange(b.southWest.latitude, b.northEast.latitude),
        );
        expect(
          p.longitude,
          inInclusiveRange(b.southWest.longitude, b.northEast.longitude),
        );
      }
      expect(b.northEast.latitude, 1.4200);
      expect(b.northEast.longitude, 103.9000);
    });

    test('the ride carries the busrouter direction index, not the kept '
        'direction position', () {
      // The parser dropped busrouter direction 0, so the one kept direction
      // (index 0 in `directions`) is busrouter's direction 1. The matcher
      // cannot tell the two directions apart reliably, so this mapping is
      // what keeps the line of the opposite direction from being drawn.
      BusStop s(String code, double lat, double lng) => BusStop(
        code: code,
        position: LatLng(lat, lng),
        name: code,
        road: 'Fake Rd',
      );
      final dropped = BusNetwork(
        stops: {
          'A': s('A', 1.3510, 103.8490),
          'B': s('B', 1.3000, 103.8400),
          'C': s('C', 1.2645, 103.8226),
        },
        services: const {
          'R3': BusService(
            number: 'R3',
            name: 'R3',
            directions: [
              ['A', 'B', 'C'],
            ],
            sourceDirections: [1],
          ),
        },
      );
      final plan = planDirectBus(dropped, bishan, vivoCity.position);
      expect(plan, isA<DirectBusOptions>());
      expect((plan as DirectBusOptions).options.first.direction, 0);
      final scene = sceneTo(
        vivoCity.position,
        plan: plan,
        stops: dropped.stops,
      );
      expect(scene.ride, isNotNull);
      expect(scene.ride!.sourceDirection, 1);
    });

    test('two scenes that differ only in the ride are not equal', () {
      const markers = [
        MapMarker(MapMarkerKind.origin, bishan, 'a'),
        MapMarker(MapMarkerKind.destination, LatLng(1.2643, 103.8223), 'b'),
      ];
      const rideA = MapRide(
        service: 'F20',
        sourceDirection: 0,
        boardIndex: 0,
        stops: [LatLng(1.35, 103.848), LatLng(1.30, 103.85)],
      );
      const rideB = MapRide(
        service: 'F20',
        sourceDirection: 0,
        boardIndex: 0,
        stops: [LatLng(1.35, 103.848), LatLng(1.31, 103.85)],
      );
      expect(
        const MapScene(markers, ride: rideA),
        const MapScene(markers, ride: rideA),
      );
      expect(
        const MapScene(markers, ride: rideA).hashCode,
        const MapScene(markers, ride: rideA).hashCode,
      );
      expect(
        const MapScene(markers, ride: rideA),
        isNot(const MapScene(markers, ride: rideB)),
      );
      expect(
        const MapScene(markers, ride: rideA),
        isNot(const MapScene(markers)),
      );
    });

    test('a plan that does not match the network draws no line and changes '
        'nothing else', () {
      // boardIndex 1 is MID1, not the option's boarding stop BSH2.
      final mismatched = BusOption(
        service: option.service,
        direction: option.direction,
        board: option.board,
        boardIndex: 1,
        alight: option.alight,
        stops: option.stops,
        walkToStop: option.walkToStop,
        walkFromStop: option.walkFromStop,
        score: option.score,
        towardName: option.towardName,
        isLoop: option.isLoop,
      );
      final scene = sceneTo(
        vivoCity.position,
        plan: DirectBusOptions([mismatched], radiusMeters: 400),
        stops: stops,
      );
      expect(scene.ride, isNull);
      expect(kinds(scene), [
        MapMarkerKind.origin,
        MapMarkerKind.boarding,
        MapMarkerKind.alighting,
        MapMarkerKind.destination,
      ]);
      expect(scene.serviceNumber, 'F20');
    });

    test('a repeated stop run gives the leading stops that pin the boarding '
        'occurrence', () {
      BusStop s(String code, double lat, double lng) => BusStop(
        code: code,
        position: LatLng(lat, lng),
        name: code,
        road: 'Fake Rd',
      );
      final a = s('A', 1.3510, 103.8490);
      final b = s('B', 1.3000, 103.8400);
      final c = s('C', 1.3200, 103.8450);
      final service = const BusService(
        number: 'R2',
        name: 'R2',
        directions: [
          ['A', 'B', 'C', 'A', 'B'],
        ],
      );
      // The planner's option boards the second pass, at index 3.
      final repeated = BusOption(
        service: service,
        direction: 0,
        board: a,
        boardIndex: 3,
        alight: b,
        stops: 1,
        walkToStop: WalkEstimate.between(bishan, a.position),
        walkFromStop: WalkEstimate.between(b.position, vivoCity.position),
        score: 1,
        towardName: 'B',
        isLoop: false,
      );
      final scene = sceneTo(
        vivoCity.position,
        plan: DirectBusOptions([repeated], radiusMeters: 400),
        stops: {'A': a, 'B': b, 'C': c},
      );
      expect(scene.ride!.boardIndex, 3);
      expect(scene.ride!.stops, [a.position, b.position]);
      expect(scene.ride!.leadingStops, [c.position]);
    });

    test('the planner boards a later occurrence: its boardIndex reaches the '
        'ride, with the leading stops that pin it', () {
      BusStop s(String code, double lat, double lng) => BusStop(
        code: code,
        position: LatLng(lat, lng),
        name: code,
        road: 'Fake Rd',
      );
      const destination = LatLng(1.3000, 103.8400);
      final a = s('A', 1.3510, 103.8490); // near the origin
      final b = s('B', 1.3002, 103.8402); // near the destination
      final x = s('X', 1.3300, 103.8600);
      final c = s('C', 1.3200, 103.8300);
      final d = s('D', 1.3400, 103.8200);
      // A → B is 2 stops from index 0 and 1 stop from index 4 or 7. The
      // planner keeps the first of equal options, so it boards at 4. The run
      // [A, B] also occurs at 7, so C (index 3) pins the occurrence.
      final repeated = BusNetwork(
        stops: {
          for (final st in [a, b, x, c, d]) st.code: st,
        },
        services: const {
          'R3': BusService(
            number: 'R3',
            name: 'R3',
            directions: [
              ['A', 'X', 'B', 'C', 'A', 'B', 'D', 'A', 'B'],
            ],
          ),
        },
      );
      final plan = planDirectBus(repeated, bishan, destination);
      final option = (plan as DirectBusOptions).options.single;
      expect(option.boardIndex, 4);
      expect(option.stops, 1);

      final ride = sceneTo(
        destination,
        plan: plan,
        stops: repeated.stops,
      ).ride!;
      expect(ride.boardIndex, 4);
      expect(ride.stops, [a.position, b.position]);
      expect(ride.leadingStops, [c.position]);
    });
  });

  group('the selected option (P2-M3)', () {
    final stops = network.stops;
    final plan =
        planDirectBus(network, bishan, vivoCity.position) as DirectBusOptions;
    // F20 BSH2 → VIV1 (suggested), F10 BSH1 → VIV1, F30 BSH1 → VIV1.
    MapScene at(int i) =>
        sceneTo(vivoCity.position, plan: plan, stops: stops, selectedIndex: i);
    LatLng pos(MapScene s, MapMarkerKind k) =>
        s.markers.firstWhere((m) => m.kind == k).position;

    test('index 0 is the suggestion; index 1 shows F10 everywhere', () {
      expect(at(0).serviceNumber, 'F20');
      expect(at(0).isAlternative, isFalse);
      final s1 = at(1);
      expect(s1.serviceNumber, 'F10');
      expect(s1.isAlternative, isTrue);
      expect(pos(s1, MapMarkerKind.boarding), stops['BSH1']!.position);
      expect(pos(s1, MapMarkerKind.alighting), stops['VIV1']!.position);
      expect(s1.ride!.service, 'F10');
      expect(s1.ride!.boardIndex, plan.options[1].boardIndex);
    });

    test('two options with the same stops are different scenes (F10, F30)', () {
      expect(
        pos(at(1), MapMarkerKind.boarding),
        pos(at(2), MapMarkerKind.boarding),
      );
      expect(
        pos(at(1), MapMarkerKind.alighting),
        pos(at(2), MapMarkerKind.alighting),
      );
      expect(at(1).ride, isNot(at(2).ride));
      expect(at(1), isNot(at(2)));
    });

    test('an out-of-range index shows the suggestion', () {
      expect(at(9).serviceNumber, 'F20');
      expect(at(9).isAlternative, isFalse);
      expect(at(-1).serviceNumber, 'F20');
    });

    test('walks: origin → boarding and alighting → destination, exactly '
        'the markers', () {
      expect(at(1).walks, [
        MapWalk(bishan, stops['BSH1']!.position),
        MapWalk(stops['VIV1']!.position, vivoCity.position),
      ]);
    });

    test('no walks without a bus: loading, walk-only, no direct bus, no '
        'stops', () {
      for (final p in <JourneyPlan?>[
        null,
        WalkOnly(WalkEstimate.between(bishan, bishan)),
        const NoDirectBus(radiusMeters: 800),
        const NoNearbyStops(JourneyEnd.origin, radiusMeters: 800),
      ]) {
        expect(
          sceneTo(vivoCity.position, plan: p, stops: stops).walks,
          isEmpty,
          reason: '$p',
        );
      }
    });

    test('a connector under walkConnectorMinMeters is left out, the other '
        'kept', () {
      final o = plan.options.first;
      final atStop = buildMapScene(
        origin: o.board.position, // the origin is the boarding stop itself
        originLabel: 'Here',
        destination: vivoCity.position,
        destinationLabel: 'Destination',
        plan: plan,
        stops: stops,
      );
      expect(atStop.walks, [MapWalk(o.alight.position, vivoCity.position)]);
    });

    test('summary: an alternative says so, and walks are called estimates', () {
      expect(
        at(1).summary,
        'Map of an alternative journey: from Current location, bus F10 from '
        'Bishan Int (fake) (BSH1) to VivoCity (fake) (VIV1), to Destination. '
        'Walks are drawn as straight lines, estimates only. '
        'The journey details are listed above.',
      );
    });
  });

  group('MRT markers (P2-M3)', () {
    // The card's own suggestions, from the unchanged journey function.
    final nearO = nearestMrtStation(fakeMrtStations, bishan)!;
    final nearD = nearestMrtStation(fakeMrtStations, vivoCity.position)!;
    final both = (nearOrigin: nearO, nearDestination: nearD);
    const mrtKinds = [
      MapMarkerKind.mrtNearOrigin,
      MapMarkerKind.mrtNearDestination,
    ];
    MapMarker? mrt(MapScene s, MapMarkerKind k) =>
        s.markers.where((m) => m.kind == k).firstOrNull;

    test('the fixtures are the stations the card names', () {
      expect(nearO.station.name, 'BISHAN MRT STATION');
      expect(nearD.station.name, 'HARBOURFRONT MRT STATION');
    });

    test("one marker per present suggestion, at its nearest exit, with the "
        "card's wording", () {
      final s = sceneTo(vivoCity.position, mrt: both);
      final o = mrt(s, MapMarkerKind.mrtNearOrigin)!;
      final d = mrt(s, MapMarkerKind.mrtNearDestination)!;
      expect(o.position, nearO.nearestExit.position);
      expect(o.label, 'Nearest MRT: BISHAN MRT STATION');
      expect(d.position, nearD.nearestExit.position);
      expect(d.label, 'Near your destination: HARBOURFRONT MRT STATION');
      // The same words as the journey card, from the one shared place.
      expect(o.label, MrtWording.named(MrtWording.nearOrigin, nearO.station));
      expect(
        d.label,
        MrtWording.named(MrtWording.nearDestination, nearD.station),
      );
    });

    test('the marker is at the nearest exit, not the first one listed', () {
      const far = MrtExit(code: 'Exit A', position: LatLng(1.3600, 103.8600));
      const near = MrtExit(code: 'Exit B', position: LatLng(1.3510, 103.8486));
      final twoExits = nearestMrtStation(const [
        MrtStation(name: 'TWO EXIT MRT STATION', exits: [far, near]),
      ], bishan)!;
      final s = sceneTo(
        vivoCity.position,
        mrt: (nearOrigin: twoExits, nearDestination: null),
      );
      expect(mrt(s, MapMarkerKind.mrtNearOrigin)!.position, near.position);
    });

    test('a side with no station within the limit has no marker', () {
      final s = sceneTo(
        vivoCity.position,
        mrt: (nearOrigin: nearO, nearDestination: null),
      );
      expect(mrt(s, MapMarkerKind.mrtNearOrigin), isNotNull);
      expect(mrt(s, MapMarkerKind.mrtNearDestination), isNull);
      expect(
        sceneTo(vivoCity.position).markers
            .where((m) => mrtKinds.contains(m.kind)),
        isEmpty,
      );
    });

    test('MRT markers come after the journey markers and never change '
        'them', () {
      final plan = planDirectBus(network, bishan, vivoCity.position);
      final withMrt = sceneTo(
        vivoCity.position,
        plan: plan,
        stops: network.stops,
        mrt: both,
      );
      final without = sceneTo(
        vivoCity.position,
        plan: plan,
        stops: network.stops,
      );
      expect(kinds(withMrt), [...kinds(without), ...mrtKinds]);
      expect(withMrt.ride, without.ride);
      expect(withMrt.walks, without.walks, reason: 'never a walk to an MRT');
    });

    test('present for every answer, independent of the plan', () {
      for (final p in <JourneyPlan?>[
        null,
        const NoDirectBus(radiusMeters: 800),
        const NoNearbyStops(JourneyEnd.destination, radiusMeters: 800),
        WalkOnly(WalkEstimate.between(bishan, bishan)),
        planDirectBus(network, bishan, vivoCity.position),
      ]) {
        final s = sceneTo(
          vivoCity.position,
          plan: p,
          stops: network.stops,
          mrt: both,
        );
        expect(mrt(s, MapMarkerKind.mrtNearOrigin), isNotNull, reason: '$p');
        expect(
          mrt(s, MapMarkerKind.mrtNearDestination),
          isNotNull,
          reason: '$p',
        );
      }
    });

    test('bounds hold the MRT markers', () {
      final b = sceneTo(vivoCity.position, mrt: both).bounds;
      for (final p in [
        nearO.nearestExit.position,
        nearD.nearestExit.position,
      ]) {
        expect(
          p.latitude,
          inInclusiveRange(b.southWest.latitude, b.northEast.latitude),
        );
        expect(
          p.longitude,
          inInclusiveRange(b.southWest.longitude, b.northEast.longitude),
        );
      }
    });

    test("summary names the marked stations with the card's wording", () {
      expect(
        sceneTo(vivoCity.position, mrt: both).summary,
        'Map of the suggested journey: from Current location, to Destination. '
        'Nearest MRT: BISHAN MRT STATION. '
        'Near your destination: HARBOURFRONT MRT STATION. '
        'The journey details are listed above.',
      );
    });

    test('scenes that differ only in MRT are not equal', () {
      expect(
        sceneTo(vivoCity.position, mrt: both),
        isNot(sceneTo(vivoCity.position)),
      );
    });
  });
}
