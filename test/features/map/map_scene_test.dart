// P2-M1: the pure journey → map-scene transformation. The plans come from the
// real planner over the fake bus network (integration_test/fakes/), so the
// stops shown are exactly the ones the journey card suggests.
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/core/geo/geo.dart';
import 'package:sg_smart_commute/features/journey/domain/direct_bus_planner.dart';
import 'package:sg_smart_commute/features/journey/domain/walking.dart';
import 'package:sg_smart_commute/features/map/domain/map_scene.dart';

import '../../../integration_test/fakes/fake_bus_network.dart';
import '../../../integration_test/fakes/fake_place_search_repository.dart';

const bishan = LatLng(1.3508, 103.8485);

MapScene sceneTo(LatLng destination, {JourneyPlan? plan}) => buildMapScene(
  origin: bishan,
  originLabel: 'Current location',
  destination: destination,
  destinationLabel: 'Destination',
  plan: plan,
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
        'Destination. The journey details are listed above.',
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
}
