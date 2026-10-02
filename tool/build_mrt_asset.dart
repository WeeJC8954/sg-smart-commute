// Builds assets/mrt_stations.json from the LTA MRT Station Exit dataset
// (data.gov.sg, Singapore Open Data Licence). Dart VM, not shipped. The app
// only reads the generated asset; it never calls this dataset at runtime.
//
//   dart run tool/build_mrt_asset.dart                 # download, then build
//   dart run tool/build_mrt_asset.dart --input exits.geojson --retrieved 2026-10-02
//
// Exits are grouped into stations by `groupMrtExits` (lib/features/journey/
// data/mrt_grouping.dart): seven code-only station names are mapped only
// through the cited, verified table there. An unmapped code-only name is kept
// as its own code-labelled station and reported, never merged by proximity.
// The output is sorted and rounded, so the same input gives the same file.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:sg_smart_commute/features/journey/data/mrt_asset.dart';
import 'package:sg_smart_commute/features/journey/data/mrt_grouping.dart';

const datasetId = 'd_b39d3a0871985372d7e1637193335da5';
const pollUrl =
    'https://api-open.data.gov.sg/v1/public/api/datasets/$datasetId/poll-download';
const outPath = 'assets/mrt_stations.json';

Future<void> main(List<String> args) async {
  String? input;
  String? retrieved;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--input') input = args[++i];
    if (args[i] == '--retrieved') retrieved = args[++i];
  }

  final String geojson;
  if (input != null) {
    geojson = await File(input).readAsString();
  } else {
    stdout.writeln('Downloading dataset $datasetId …');
    final poll = await http.get(Uri.parse(pollUrl));
    if (poll.statusCode != 200 && poll.statusCode != 201) {
      stderr.writeln('poll-download HTTP ${poll.statusCode}');
      exit(1);
    }
    final url = (jsonDecode(poll.body) as Map)['data']['url'] as String;
    final file = await http.get(Uri.parse(url));
    if (file.statusCode != 200) {
      stderr.writeln('download HTTP ${file.statusCode}');
      exit(1);
    }
    geojson = utf8.decode(file.bodyBytes);
  }
  retrieved ??= DateTime.now().toUtc().toIso8601String().substring(0, 10);

  final features = (jsonDecode(geojson) as Map)['features'] as List;
  final raw = <RawMrtExit>[];
  var skipped = 0;
  var latestUpdate = '';
  for (final f in features.cast<Map<String, dynamic>>()) {
    final props = f['properties'] as Map<String, dynamic>;
    final geometry = f['geometry'] as Map<String, dynamic>?;
    final coords = geometry?['coordinates'];
    final name = props['STATION_NA'];
    final exitCode = props['EXIT_CODE'];
    if (geometry?['type'] != 'Point' ||
        coords is! List ||
        coords.length < 2 ||
        name is! String ||
        exitCode is! String) {
      skipped++;
      continue;
    }
    final update = '${props['FMEL_UPD_D'] ?? ''}';
    if (update.compareTo(latestUpdate) > 0) latestUpdate = update;
    // GeoJSON order is [longitude, latitude].
    raw.add(
      RawMrtExit(
        stationName: name,
        exitCode: exitCode,
        latitude: (coords[1] as num).toDouble(),
        longitude: (coords[0] as num).toDouble(),
      ),
    );
  }

  final result = groupMrtExits(raw);
  final asset = {
    'source': {
      'dataset': 'LTA MRT Station Exit (GEOJSON)',
      'datasetId': datasetId,
      'publisher': 'Land Transport Authority, via data.gov.sg',
      'licence': 'Singapore Open Data Licence v1.0',
      'retrieved': retrieved,
      'datasetLatestFeatureUpdate': latestUpdate,
      'generator': 'tool/build_mrt_asset.dart',
    },
    'codeOnlyMappings': [
      for (final c in verifiedCodeOnlyStations)
        {'code': c.code, 'name': c.name, 'evidence': c.evidence},
    ],
    'counts': {
      'features': features.length,
      'skippedFeatures': skipped,
      'exits': result.exitCount,
      'duplicateExits': result.duplicateExits,
      'stations': result.stations.length,
      'codeOnlyMapped': result.mappedCodeOnly.length,
      'codeOnlyUnverified': result.unverifiedCodeOnly.length,
    },
    'stations': encodeMrtStations(result.stations),
  };

  // Round-trip check: the app's own parser must accept what was written.
  final text = '${const JsonEncoder.withIndent(' ').convert(asset)}\n';
  parseMrtAsset(jsonDecode(text));
  await File(outPath).writeAsString(text);

  stdout
    ..writeln('Wrote $outPath')
    ..writeln('  features ${features.length}, skipped $skipped')
    ..writeln(
      '  exits ${result.exitCount}, duplicates ${result.duplicateExits}',
    )
    ..writeln('  stations ${result.stations.length}')
    ..writeln('  code-only mapped: ${result.mappedCodeOnly.join(', ')}');
  if (result.unverifiedCodeOnly.isNotEmpty) {
    stdout.writeln(
      '  WARNING unverified code-only stations kept separate: '
      '${result.unverifiedCodeOnly.join(', ')}',
    );
  }
}
