// Driver for integration_test/demo/readme_screenshots.dart: like
// integration_test.dart, but each `takeScreenshot` is saved as
// build/readme_screenshots/<name>.png.
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() => integrationDriver(
  onScreenshot: (name, bytes, [args]) async {
    final file = File('build/readme_screenshots/$name.png');
    await file.create(recursive: true);
    await file.writeAsBytes(bytes);
    return true;
  },
);
