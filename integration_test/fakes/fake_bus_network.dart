import 'dart:async';
import 'dart:convert';

import 'package:sg_smart_commute/core/errors/app_failure.dart';
import 'package:sg_smart_commute/core/geo/geo.dart';
import 'package:sg_smart_commute/features/journey/data/mrt_asset.dart';
import 'package:sg_smart_commute/features/journey/data/mrt_asset_repository.dart';
import 'package:sg_smart_commute/features/journey/domain/bus_network.dart';
import 'package:sg_smart_commute/features/journey/domain/bus_network_repository.dart';
import 'package:sg_smart_commute/features/journey/domain/mrt.dart';

/// A small fake bus network around the fake places (integration_test/fakes/
/// fake_place_search_repository.dart) and the fake GPS fix at Bishan
/// (1.3508, 103.8485). Service numbers start with F so they can never be
/// mistaken for real data. Bishan → VivoCity:
///
///   F20  BSH2 → VIV1  2 stops  walk 2 + 1  score 6   (Suggested)
///   F10  BSH1 → VIV1  3 stops  walk 1 + 1  score 6.5
///   F30  BSH1 → VIV1  3 stops  walk 1 + 1  score 6.5 (ties F10 → number)
///
/// Bishan → ION Orchard: F30 BSH1 → ION1, 1 stop. Tampines Hub → ION Orchard:
/// no direct bus (F40 only reaches MID1).
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
    s('VIV1', 'VivoCity (fake)', 1.2645, 103.8226),
    s('ION1', 'Orchard Stn (fake)', 1.3042, 103.8318),
    s('TPH1', 'Tampines Hub (fake)', 1.3532, 103.9402),
    s('MID1', 'Midway (fake)', 1.3000, 103.8500),
    s('MID2', 'Halfway (fake)', 1.2800, 103.8300),
  ];
  BusService svc(String number, List<List<String>> directions) =>
      BusService(number: number, name: 'Fake $number', directions: directions);
  final services = [
    svc('F10', [
      ['BSH1', 'MID1', 'MID2', 'VIV1'],
      ['VIV1', 'MID2', 'MID1', 'BSH2'],
    ]),
    svc('F20', [
      ['BSH2', 'MID1', 'VIV1'],
    ]),
    svc('F30', [
      ['BSH1', 'ION1', 'MID2', 'VIV1'],
    ]),
    svc('F40', [
      ['TPH1', 'MID1'],
    ]),
  ];
  return BusNetwork(
    stops: {for (final x in stops) x.code: x},
    services: {for (final x in services) x.number: x},
  );
}

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

const fakeMrtStations = [
  MrtStation(
    name: 'BISHAN MRT STATION',
    exits: [MrtExit(code: 'Exit A', position: LatLng(1.3510, 103.8483))],
  ),
  MrtStation(
    name: 'HARBOURFRONT MRT STATION',
    exits: [MrtExit(code: 'Exit E', position: LatLng(1.2653, 103.8220))],
  ),
  MrtStation(
    name: 'ORCHARD MRT STATION',
    exits: [MrtExit(code: 'Exit 1', position: LatLng(1.3040, 103.8318))],
  ),
  MrtStation(
    name: 'TAMPINES MRT STATION',
    exits: [MrtExit(code: 'Exit A', position: LatLng(1.3540, 103.9450))],
  ),
];

/// The real asset repository over a small fake asset (no rootBundle).
MrtAssetRepository fakeMrtRepository({bool fail = false}) => MrtAssetRepository(
  load: () async {
    if (fail) throw Exception('asset missing');
    return jsonEncode({'stations': encodeMrtStations(fakeMrtStations)});
  },
);
