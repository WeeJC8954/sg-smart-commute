// Hand-made synthetic OneMap search responses for the place-search tests
// (owner decisions A-4b and A-4c, docs/arrivelah-onemap-fixture-licensing-audit.md).
// They replace live captures, whose redistribution is not shown to be
// permitted. Nothing here is copied from OneMap or any other source: only the
// field names and the body shape are OneMap's. Names end in "(fake)", roads
// are "FAKE ROAD", postal codes are in the unused sectors 00 and 99, the error
// text is invented, and every position comes from [_row]'s grid formula. Each
// body is JSON text, so the tests still decode and parse the whole response.
// The cases are listed in README.md here.
import 'dart:convert';

/// Stands in for the message a tokenless OneMap body always carries, even
/// next to results or an empty list. The parser only checks that it exists.
const syntheticTokenMessage = 'Synthetic token message (fake).';

/// One result row with every field a live row has. Case [k], row [r] sits at
/// latitude 1.20 + 0.02k + 0.001r and longitude 103.70 + 0.03k + 0.001r
/// (inside the app's SG box for k ≤ 6), unless [lat] overrides it. X and Y
/// are SVY21-shaped (20000 + 1000k + 10r, 30000 + 1000k + 10r); the app
/// ignores them.
Map<String, String> _row(
  int k,
  int r,
  String name, {
  String block = '',
  String road = 'NIL',
  String building = 'NIL',
  String address = 'NIL',
  String postal = 'NIL',
  double? lat,
}) => {
  'SEARCHVAL': name,
  'BLK_NO': block,
  'ROAD_NAME': road,
  'BUILDING': building,
  'ADDRESS': address,
  'POSTAL': postal,
  'X': '${20000 + 1000 * k + 10 * r}.5',
  'Y': '${30000 + 1000 * k + 10 * r}.5',
  'LATITUDE': (lat ?? 1.20 + 0.02 * k + 0.001 * r).toStringAsFixed(6),
  'LONGITUDE': (103.70 + 0.03 * k + 0.001 * r).toStringAsFixed(6),
};

String _response(List<Map<String, String>> rows) =>
    const JsonEncoder.withIndent('  ').convert({
      'error': syntheticTokenMessage,
      'found': rows.length,
      'totalNumPages': rows.isEmpty ? 0 : 1,
      'pageNum': 1,
      'results': rows,
    });

/// Case 1: a postal-code search with one building, whose postcode starts
/// with 0 (latitude 1.221, longitude 103.731).
final postalLeadingZeroBody = _response([
  _row(
    1,
    1,
    'FAKE PLAZA (fake)',
    block: '1',
    road: 'FAKE ROAD',
    building: 'FAKE PLAZA (fake)',
    address: '1 FAKE ROAD FAKE PLAZA (fake) SINGAPORE 009901',
    postal: '009901',
  ),
]);

/// Case 2: a block search. The block itself (an address: no building) with
/// its postcode, then a home in the same block with a "NIL" postcode.
final hdbBlockBody = _response([
  _row(
    2,
    1,
    '901 FAKE ROAD 9 SINGAPORE 990901 (fake)',
    block: '901',
    road: 'FAKE ROAD 9',
    address: '901 FAKE ROAD 9 SINGAPORE 990901 (fake)',
    postal: '990901',
  ),
  _row(
    2,
    2,
    'FAKE COMMUNITY HOME (fake)',
    block: '901',
    road: 'FAKE ROAD 9',
    building: 'FAKE COMMUNITY HOME (fake)',
    address: '901 FAKE ROAD 9 FAKE COMMUNITY HOME (fake)',
  ),
]);

/// Case 3: a station search. A station with a "NIL" postcode first, two coded
/// platforms, an exit with an empty block, and an LRT station.
final mrtStationBody = _response([
  _row(
    3,
    1,
    'FAKE MRT STATION (fake)',
    block: '7',
    road: 'FAKE ROAD',
    building: 'FAKE MRT STATION (fake)',
    address: '7 FAKE ROAD FAKE MRT STATION (fake)',
  ),
  _row(
    3,
    2,
    'FAKE MRT STATION (FK1) (fake)',
    block: '7',
    road: 'FAKE ROAD',
    building: 'FAKE MRT STATION (FK1) (fake)',
    address: '7 FAKE ROAD FAKE MRT STATION (FK1) (fake) SINGAPORE 990011',
    postal: '990011',
  ),
  _row(
    3,
    3,
    'FAKE MRT STATION (FK2) (fake)',
    block: '8',
    road: 'FAKE ROAD',
    building: 'FAKE MRT STATION (FK2) (fake)',
    address: '8 FAKE ROAD FAKE MRT STATION (FK2) (fake) SINGAPORE 990012',
    postal: '990012',
  ),
  _row(
    3,
    4,
    'FAKE MRT STATION EXIT A (fake)',
    building: 'FAKE MRT STATION EXIT A (fake)',
    address: 'FAKE MRT STATION EXIT A (fake)',
  ),
  _row(
    3,
    5,
    'FAKE LRT STATION (FL1) (fake)',
    building: 'FAKE LRT STATION (FL1) (fake)',
    address: 'FAKE LRT STATION (FL1) (fake)',
  ),
]);

/// Case 4: a street search, in the provider's order (not alphabetical). The
/// road appears twice (once as a road, once as a building of that name), and
/// one row lies north of the SG box (latitude 1.50) and is dropped.
final streetBody = _response([
  _row(
    4,
    1,
    'THE FAKE HOTEL ON FAKE ROAD (fake)',
    block: '20',
    road: 'FAKE LANE',
    building: 'THE FAKE HOTEL ON FAKE ROAD (fake)',
    address: '20 FAKE LANE THE FAKE HOTEL ON FAKE ROAD (fake) SINGAPORE 990021',
    postal: '990021',
  ),
  _row(4, 2, 'FAKE ROAD (fake)', address: 'FAKE ROAD (fake)'),
  _row(
    4,
    3,
    'FAKE ROAD (fake)',
    block: '2',
    road: 'FAKE TURN',
    building: 'FAKE ROAD (fake)',
    address: '2 FAKE TURN FAKE ROAD (fake)',
  ),
  _row(
    4,
    4,
    'FAKE ROAD - ERP(99) (fake)',
    building: 'FAKE ROAD - ERP(99) (fake)',
    address: 'FAKE ROAD - ERP(99) (fake)',
  ),
  _row(
    4,
    5,
    'FAKE ROAD NORTH (fake)',
    building: 'FAKE ROAD NORTH (fake)',
    address: 'FAKE ROAD NORTH (fake)',
    lat: 1.50,
  ),
  _row(
    4,
    6,
    'FAKE ROAD CHAPEL (fake)',
    block: '3',
    road: 'FAKE ROAD',
    building: 'FAKE ROAD CHAPEL (fake)',
    address: '3 FAKE ROAD FAKE ROAD CHAPEL (fake) SINGAPORE 990022',
    postal: '990022',
  ),
]);

/// Case 5: a name search for a mall, answered by the mall and a station named
/// after it, with different postcodes.
final mallBody = _response([
  _row(
    5,
    1,
    'FAKE MALL (fake)',
    block: '1',
    road: 'FAKE WALK',
    building: 'FAKE MALL (fake)',
    address: '1 FAKE WALK FAKE MALL (fake) SINGAPORE 990031',
    postal: '990031',
  ),
  _row(
    5,
    2,
    'FAKE MALL STATION (FS1) (fake)',
    block: '83',
    road: 'FAKE ROAD',
    building: 'FAKE MALL STATION (FS1) (fake)',
    address: '83 FAKE ROAD FAKE MALL STATION (FS1) (fake) SINGAPORE 990032',
    postal: '990032',
  ),
]);

/// Case 6: one result next to the token message (the normal tokenless body).
final tokenWithResultBody = _response([
  _row(
    6,
    1,
    'FAKE ARCADE (fake)',
    block: '2',
    road: 'FAKE TURN',
    building: 'FAKE ARCADE (fake)',
    address: '2 FAKE TURN FAKE ARCADE (fake) SINGAPORE 990041',
    postal: '990041',
  ),
]);

/// Case 7: a postal code that matches nothing (`000000`): the token message
/// and an empty list.
final postalNoMatchBody = _response([]);

/// Case 8: a raw "Blk …" query that matches nothing: the same empty shape.
final blockNoMatchBody = _response([]);
