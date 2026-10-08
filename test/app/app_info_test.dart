// E4: the version and build come only from the build (Flutter's
// appBuildName / appBuildNumber), never from a literal in lib/.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/app/app_info.dart';

/// pubspec `version: <name>+<number>`.
({String name, String number}) pubspecVersion() {
  final m = RegExp(
    r'^version:\s*([^+\s]+)\+(\S+)\s*$',
    multiLine: true,
  ).firstMatch(File('pubspec.yaml').readAsStringSync())!;
  return (name: m[1]!, number: m[2]!);
}

void main() {
  test('label: version and build, or the version alone', () {
    expect(
      const AppInfo(version: '9.8.7', buildNumber: '42').label,
      'Version 9.8.7 (42)',
    );
    expect(
      const AppInfo(version: '9.8.7', buildNumber: '').label,
      'Version 9.8.7',
    );
  });

  test('appInfoFrom: no name means no version; a missing number is empty', () {
    expect(appInfoFrom(null, '42'), isNull);
    expect(appInfoFrom('', '42'), isNull);
    expect(appInfoFrom('9.8.7', null)?.label, 'Version 9.8.7');
    expect(appInfoFrom('9.8.7', '42')?.label, 'Version 9.8.7 (42)');
  });

  test('the real provider carries the pubspec version, compiled in by the '
      'flutter tool', () {
    final v = pubspecVersion();
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      container.read(appInfoProvider)?.label,
      'Version ${v.name} (${v.number})',
    );
  });

  test('lib/ never spells out the version: it comes only from the build', () {
    final v = pubspecVersion();
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    for (final f in files) {
      expect(f.readAsStringSync(), isNot(contains(v.name)), reason: f.path);
    }
  });
}
