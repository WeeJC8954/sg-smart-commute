// Dart VM runner of the E5 benchmark (README.md):
//
//   dart run tool/e5_transfer_bench/vm_main.dart
import 'dart:io';

import 'bench.dart';

void main() {
  const data = 'test/fixtures/busrouter/snapshot-2026-11-06';
  stdout.write(
    runBenchmark(
      File('$data/stops.min.json').readAsStringSync(),
      File('$data/services.min.json').readAsStringSync(),
      platform: 'Dart VM ${Platform.version.split(' ').first}',
    ),
  );
}
