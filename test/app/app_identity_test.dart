// E3: the platform icons and visible names carry the app's identity, not
// Flutter's project template. Reads the platform files directly.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/app/app.dart';
import 'package:sg_smart_commute/app/app_logo.dart';

const res = 'android/app/src/main/res';

/// Width and height from a PNG's IHDR chunk.
({int width, int height}) png(String path) {
  final b = File(path).readAsBytesSync();
  expect(b.sublist(1, 4), 'PNG'.codeUnits, reason: path);
  int u32(int at) => b[at] << 24 | b[at + 1] << 16 | b[at + 2] << 8 | b[at + 3];
  return (width: u32(16), height: u32(20));
}

/// Flutter's untouched project-template icons, by byte length (Phase A A0
/// audit of main @ 53acc19): a file this exact length here is the template.
const templateLengths = {
  '$res/mipmap-mdpi/ic_launcher.png': 442,
  '$res/mipmap-hdpi/ic_launcher.png': 544,
  '$res/mipmap-xhdpi/ic_launcher.png': 721,
  '$res/mipmap-xxhdpi/ic_launcher.png': 1031,
  '$res/mipmap-xxxhdpi/ic_launcher.png': 1443,
  'web/favicon.png': 917,
  'web/icons/Icon-192.png': 5292,
  'web/icons/Icon-512.png': 8252,
  'web/icons/Icon-maskable-192.png': 5594,
  'web/icons/Icon-maskable-512.png': 20998,
};

void notTemplate(String path) => expect(
  File(path).lengthSync(),
  isNot(templateLengths[path]),
  reason: '$path is still the Flutter template icon',
);

void main() {
  test("the icon master is the owner's original artwork, untouched", () {
    const master = 'tool/icon/app_icon_master.png';
    expect(png(master), (width: 1254, height: 1254));
    expect(File(master).lengthSync(), 1235421);
  });

  test('Android: the launcher uses the app icon and the human name', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    expect(manifest, contains('android:label="${SmartCommuteApp.title}"'));
    expect(manifest, contains('android:icon="@mipmap/ic_launcher"'));
    expect(manifest, isNot(contains('sg_smart_commute"')));
  });

  test('Android: legacy icons at every density, none the template', () {
    const sizes = {
      'mdpi': 48,
      'hdpi': 72,
      'xhdpi': 96,
      'xxhdpi': 144,
      'xxxhdpi': 192,
    };
    sizes.forEach((density, px) {
      final path = '$res/mipmap-$density/ic_launcher.png';
      expect(png(path), (width: px, height: px), reason: path);
      notTemplate(path);
    });
  });

  test('Android 8+: an adaptive icon on white whose layers exist', () {
    final xml = File('$res/mipmap-anydpi-v26/ic_launcher.xml')
        .readAsStringSync();
    expect(xml, contains('@drawable/ic_launcher_foreground'));
    expect(xml, contains('@color/ic_launcher_background'));
    expect(
      File('$res/values/colors.xml').readAsStringSync(),
      contains('<color name="ic_launcher_background">#FFFFFF</color>'),
    );
    const sizes = {
      'mdpi': 108,
      'hdpi': 162,
      'xhdpi': 216,
      'xxhdpi': 324,
      'xxxhdpi': 432,
    };
    sizes.forEach((density, px) {
      final path = '$res/drawable-$density/ic_launcher_foreground.png';
      expect(png(path), (width: px, height: px), reason: path);
    });
  });

  test('Web: names, white identity colours, icons at their stated sizes', () {
    final manifest = jsonDecode(
      File('web/manifest.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(manifest['name'], SmartCommuteApp.title);
    expect(manifest['short_name'], SmartCommuteApp.title);
    expect(
      (manifest['background_color'], manifest['theme_color']),
      ('#FFFFFF', '#FFFFFF'),
      reason: "white replaces Flutter's template blue (owner decision O4)",
    );
    final icons = (manifest['icons'] as List).cast<Map<String, dynamic>>();
    expect(icons, hasLength(4));
    for (final icon in icons) {
      final path = 'web/${icon['src']}';
      final px = int.parse((icon['sizes'] as String).split('x').first);
      expect(png(path), (width: px, height: px), reason: path);
      notTemplate(path);
    }
    for (final px in [192, 512]) {
      expect(
        File('web/icons/Icon-maskable-$px.png').readAsBytesSync(),
        isNot(File('web/icons/Icon-$px.png').readAsBytesSync()),
        reason: 'maskable icons carry their own safe-zone padding',
      );
    }
    notTemplate('web/favicon.png');
    final html = File('web/index.html').readAsStringSync();
    expect(html, contains('<title>${SmartCommuteApp.title}</title>'));
    expect(
      html,
      contains(
        '<meta name="apple-mobile-web-app-title" '
        'content="${SmartCommuteApp.title}">',
      ),
    );
  });

  test('the in-app logo is still the canonical 192 px art asset', () {
    expect(AppLogo.asset, 'assets/app_icon.png');
    expect(png(AppLogo.asset), (width: 192, height: 192));
  });
}
