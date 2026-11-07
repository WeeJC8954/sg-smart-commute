import 'dart:async';
import 'dart:convert';

import 'package:sg_smart_commute/core/errors/app_failure.dart';
import 'package:sg_smart_commute/core/geo/geo.dart';
import 'package:sg_smart_commute/features/journey/data/mrt_asset.dart';
import 'package:sg_smart_commute/features/journey/data/mrt_asset_repository.dart';
import 'package:sg_smart_commute/features/journey/domain/bus_network.dart';
import 'package:sg_smart_commute/features/journey/domain/bus_network_repository.dart';
import 'package:sg_smart_commute/features/journey/domain/mrt.dart';
import 'package:sg_smart_commute/features/places/domain/place.dart';

import 'fake_place_search_repository.dart';

/// A small fake bus network around the synthetic places (integration_test/
/// fakes/fake_place_search_repository.dart, README_places.md) and the fake GPS
/// fix at Bishan (1.3508, 103.8485). Service numbers start with F so they can
/// never be mistaken for real data. Each place's stop sits a few metres from
/// it ([_near]); MID1 and MID2 are placed so the rides keep the lengths (and
/// so the estimated minutes) the tests expect. Bishan → Bay Mall:
///
///   F20  BSH2 → BAY1  2 stops  walk 2 + 1  score 6   (Suggested)
///   F10  BSH1 → BAY1  3 stops  walk 1 + 1  score 6.5
///   F30  BSH1 → BAY1  3 stops  walk 1 + 1  score 6.5 (ties F10 → number)
///
/// Bishan → City Tower: F30 BSH1 → CTY1, 1 stop. East Hub → City Tower: no
/// direct bus (F40 only reaches MID1).
BusNetwork fakeBusNetwork() {
  BusStop s(String code, String name, double lat, double lng) => BusStop(
    code: code,
    position: LatLng(lat, lng),
    name: name,
    road: 'Fake Rd',
  );
  final stops = [
    s('BSH1', 'Bishan Int (fake)', 1.3510, 103.8490),
    s('BSH2', 'Opp Bishan Stn (fake)', 1.3500, 103.8480),
    _near(fakeBayMall, 'BAY1', 'Bay Mall (fake)', 0.0002, 0.0003),
    _near(fakeCityTower, 'CTY1', 'City Tower Stn (fake)', 0.0002, -0.0002),
    _near(fakeEastHub, 'EST1', 'East Hub (fake)', 0.0002, -0.0003),
    s('MID1', 'Midway (fake)', 1.3200, 103.8300),
    s('MID2', 'Halfway (fake)', 1.3100, 103.7900),
  ];
  BusService svc(String number, List<List<String>> directions) =>
      BusService(number: number, name: 'Fake $number', directions: directions);
  final services = [
    svc('F10', [
      ['BSH1', 'MID1', 'MID2', 'BAY1'],
      ['BAY1', 'MID2', 'MID1', 'BSH2'],
    ]),
    svc('F20', [
      ['BSH2', 'MID1', 'BAY1'],
    ]),
    svc('F30', [
      ['BSH1', 'CTY1', 'MID2', 'BAY1'],
    ]),
    svc('F40', [
      ['EST1', 'MID1'],
    ]),
  ];
  return BusNetwork(
    stops: {for (final x in stops) x.code: x},
    services: {for (final x in services) x.number: x},
  );
}

/// A stop at [place]'s position moved by [dLat], [dLng] degrees.
BusStop _near(
  Place place,
  String code,
  String name,
  double dLat,
  double dLng,
) => BusStop(
  code: code,
  position: _offset(place, dLat, dLng),
  name: name,
  road: 'Fake Rd',
);

LatLng _offset(Place place, double dLat, double dLng) =>
    LatLng(place.latitude + dLat, place.longitude + dLng);

/// Controllable [BusNetworkRepository]: returns [network], or throws
/// [failure]; [hold] keeps the load pending until [release].
class FakeBusNetworkRepository implements BusNetworkRepository {
  FakeBusNetworkRepository({BusNetwork? network, this.failure})
    : network = network ?? fakeBusNetwork();

  final BusNetwork network;
  AppFailure? failure;
  int loads = 0;
  Completer<void>? _gate;

  void hold() => _gate = Completer<void>();
  void release() => _gate?.complete();

  @override
  Future<BusNetwork> load() async {
    loads++;
    final gate = _gate;
    if (gate != null) await gate.future;
    final f = failure;
    if (f != null) throw f;
    return network;
  }
}

/// The fake MRT asset: one station by the fake GPS fix (its exit a few metres
/// from the fix) and one by each synthetic destination, its exit placed from
/// that place, so every place's nearest station is its own.
final fakeMrtStations = [
  const MrtStation(
    name: 'BISHAN MRT STATION',
    exits: [MrtExit(code: 'Exit A', position: LatLng(1.3512, 103.8481))],
  ),
  MrtStation(
    name: 'FAKE BAY MRT STATION',
    exits: [
      MrtExit(code: 'Exit E', position: _offset(fakeBayMall, 0.0010, -0.0003)),
    ],
  ),
  MrtStation(
    name: 'FAKE CITY MRT STATION',
    exits: [
      MrtExit(code: 'Exit 1', position: _offset(fakeCityTower, 0, -0.0002)),
    ],
  ),
  MrtStation(
    name: 'FAKE EAST MRT STATION',
    exits: [
      MrtExit(code: 'Exit A', position: _offset(fakeEastHub, 0.0010, 0.0045)),
    ],
  ),
];

/// The real asset repository over a small fake asset (no rootBundle).
MrtAssetRepository fakeMrtRepository({bool fail = false}) => MrtAssetRepository(
  load: () async {
    if (fail) throw Exception('asset missing');
    return jsonEncode({'stations': encodeMrtStations(fakeMrtStations)});
  },
);
