// #125: the synthetic test build keeps the chosen palette across a restart,
// the way main() does. Reads the entry point as text: test/ never imports
// from integration_test/ beyond the shared fakes.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the synthetic entry point reads and writes the real palette store', () {
    final src = File('integration_test/demo/synthetic_demo_app.dart')
        .readAsStringSync();
    expect(src, contains('final store = SharedPreferencesPaletteStore();'));
    expect(src, contains('palette: await loadInitialPalette(store),'));
    expect(src, contains('paletteStore: store,'));
  });

  test('the synthetic entry point, and only it, turns on prefix search', () {
    final src = File('integration_test/demo/synthetic_demo_app.dart')
        .readAsStringSync();
    expect(src, contains('FakePlaceSearchRepository(prefixMatch: true)'));
    final others =
        [
          ...Directory('integration_test').listSync(recursive: true),
          ...Directory('test').listSync(recursive: true),
        ].whereType<File>().where(
          (f) =>
              f.path.endsWith('.dart') &&
              !f.path.endsWith('synthetic_demo_app.dart') &&
              !f.path.endsWith('fake_place_search_repository.dart') &&
              !f.path.endsWith('fake_place_search_repository_test.dart') &&
              !f.path.endsWith('synthetic_demo_app_test.dart'),
        );
    for (final f in others) {
      expect(
        f.readAsStringSync(),
        isNot(contains('prefixMatch: true')),
        reason: f.path,
      );
    }
  });
}
