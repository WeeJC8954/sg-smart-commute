import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/app/home_screen.dart';
import 'package:sg_smart_commute/core/location/location_service.dart';
import 'package:sg_smart_commute/features/appearance/domain/app_palette.dart';
import 'package:sg_smart_commute/features/appearance/presentation/palette_theme.dart';

import '../../integration_test/fakes/fake_environment_repository.dart';
import '../../integration_test/fakes/fake_location_service.dart';
import '../../integration_test/fakes/test_app.dart';

const paletteFile = 'features/appearance/domain/app_palette.dart';

/// Fixed colours in the .dart files under [lib], as `lib/<path>:<line> <match>`.
/// Colors.x, Color(…) and Color.from…(…) in code; text after `//` is dropped
/// as a comment. ponytail: a line scan, not a Dart parser — `//` inside a
/// string hides the rest of that line, and a /* block */ comment is scanned.
/// Add a parser only if that ever misleads.
List<String> fixedColours(Directory lib) {
  final fixed = RegExp(r'Colors\s*\.\s*\w+|\bColor\s*(?:\.\s*from\w*\s*)?\(');
  final found = <String>[];
  for (final file in lib.listSync(recursive: true)) {
    if (file is! File || !file.path.endsWith('.dart')) continue;
    final code = file
        .readAsLinesSync()
        .map((line) => line.split('//').first)
        .join('\n');
    final path = 'lib/${file.path.substring(lib.path.length + 1)}'.replaceAll(
      r'\',
      '/',
    );
    for (final m in fixed.allMatches(code)) {
      final line = '\n'.allMatches(code.substring(0, m.start)).length + 1;
      found.add('$path:$line ${m[0]}');
    }
  }
  return found;
}

/// The seeds: one `Color(0x…)` on each compiled AppPalette value's own line
/// in [paletteFile]; everything else is a stray fixed colour.
({List<String> seeds, List<String> others}) splitSeeds(Directory lib) {
  final lines = File('${lib.path}/$paletteFile').readAsLinesSync();
  final at = RegExp('^lib/${RegExp.escape(paletteFile)}:(\\d+) Color\\(\$');
  bool isSeed(String found) {
    final m = at.firstMatch(found);
    if (m == null) return false;
    final line = lines[int.parse(m[1]!) - 1].trim();
    return AppPalette.values.any(
      (p) => RegExp(
        "^${p.name}\\('${p.id}', '${RegExp.escape(p.label)}', "
        r'Color\(0x[0-9A-F]{8}\)\)[,;]$',
      ).hasMatch(line),
    );
  }

  final found = fixedColours(lib);
  return (
    seeds: found.where(isSeed).toList(),
    others: found.where((f) => !isSeed(f)).toList(),
  );
}

/// A copy of lib/ in a temporary directory, for the guard's own checks.
Directory copyOfLib() {
  final tmp = Directory.systemTemp.createTempSync('lib-copy');
  addTearDown(() => tmp.deleteSync(recursive: true));
  final lib = Directory('${tmp.path}/lib');
  for (final f in Directory('lib').listSync(recursive: true)) {
    if (f is! File) continue;
    final to = File('${lib.path}/${f.path.substring('lib'.length + 1)}');
    to.parent.createSync(recursive: true);
    f.copySync(to.path);
  }
  return lib;
}

void main() {
  test('every palette: light and dark schemes from its one seed', () {
    for (final p in AppPalette.values) {
      for (final b in Brightness.values) {
        final theme = paletteTheme(p, b);
        expect(theme.brightness, b);
        expect(
          theme.colorScheme,
          ColorScheme.fromSeed(seedColor: p.seed, brightness: b),
        );
        expect(
          identical(theme, paletteTheme(p, b)),
          isTrue,
          reason: 'built once',
        );
      }
    }
  });

  test("the default palette is today's teal theme, unchanged", () {
    for (final b in Brightness.values) {
      expect(
        paletteTheme(AppPalette.fallback, b).colorScheme,
        ColorScheme.fromSeed(seedColor: Colors.teal, brightness: b),
      );
    }
  });

  test('the five palettes look different in light and dark', () {
    for (final b in Brightness.values) {
      expect(
        AppPalette.values
            .map((p) => paletteTheme(p, b).colorScheme.primary)
            .toSet(),
        hasLength(AppPalette.values.length),
      );
    }
  });

  for (final brightness in Brightness.values) {
    testWidgets('the app follows a ${brightness.name} system setting', (
      tester,
    ) async {
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpWidget(
        buildTestApp(
          location: FakeLocationService(access: LocationAccess.denied),
          environment: FakeEnvironmentRepository(),
        ),
      );
      await tester.pump();
      final context = tester.element(find.byType(HomeScreen));
      expect(Theme.of(context).brightness, brightness);
      expect(
        Theme.of(context).colorScheme,
        paletteTheme(AppPalette.teal, brightness).colorScheme,
      );
    });
  }

  test('lib/ takes its colours from the theme scheme; the five palette seeds '
      'are the only fixed colours', () {
    final split = splitSeeds(Directory('lib'));
    expect(AppPalette.values, hasLength(5));
    expect(
      split.seeds,
      hasLength(5),
      reason: 'one seed declaration per palette',
    );
    expect(
      split.others,
      isEmpty,
      reason: 'take colours from Theme.of(context).colorScheme',
    );
  });

  group('the colour guard catches', () {
    test('a fixed colour in the palette file off a seed line', () {
      final lib = copyOfLib();
      File('${lib.path}/$paletteFile').writeAsStringSync(
        '\nconst extra = Color(0xFF000000);\n',
        mode: FileMode.append,
      );
      expect(splitSeeds(lib).others, hasLength(1));
    });

    test('Colors.teal brought back into app.dart', () {
      final lib = copyOfLib();
      File('${lib.path}/app/app.dart').writeAsStringSync(
        '\nconst seed = Colors.teal;\n',
        mode: FileMode.append,
      );
      expect(splitSeeds(lib).others, [
        matches(r'^lib/app/app\.dart:\d+ Colors\.teal$'),
      ]);
    });

    test('a seed-like line for a value that is not in the enum', () {
      final lib = copyOfLib();
      File('${lib.path}/$paletteFile').writeAsStringSync(
        "\n  indigo('indigo', 'Indigo', Color(0xFF3F51B5)),\n",
        mode: FileMode.append,
      );
      expect(splitSeeds(lib).others, hasLength(1));
    });

    test('a stray Color( elsewhere in lib/', () {
      final lib = copyOfLib();
      File('${lib.path}/app/home_screen.dart').writeAsStringSync(
        '\nconst stray = Color(0xFF123456);\n',
        mode: FileMode.append,
      );
      final split = splitSeeds(lib);
      expect(split.others, [
        matches(r'^lib/app/home_screen\.dart:\d+ Color\($'),
      ]);
      expect(split.seeds, hasLength(5));
    });
  });
}
