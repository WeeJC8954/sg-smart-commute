// The Web Content-Security-Policy (web/index.html, M5) must stay in step with
// the providers in app_config.dart: a provider the policy does not list fails
// in the browser with a CSP error, which no VM test would notice.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/core/config/app_config.dart';

Map<String, List<String>> _policy() {
  final html = File('web/index.html').readAsStringSync();
  final meta = RegExp(
    r'<meta http-equiv="Content-Security-Policy" content="([^"]+)">',
  ).firstMatch(html);
  expect(meta, isNotNull, reason: 'web/index.html has no CSP <meta>');
  return {
    for (final directive in meta!.group(1)!.split(';'))
      if (directive.trim().isNotEmpty)
        directive.trim().split(RegExp(r'\s+')).first: directive
            .trim()
            .split(RegExp(r'\s+'))
            .skip(1)
            .toList(),
  };
}

void main() {
  test('connect-src allows every provider endpoint, and nothing else', () {
    final providers = {
      NeaEndpoints.twoHourForecast,
      NeaEndpoints.uv,
      NeaEndpoints.pm25,
      NeaEndpoints.psi,
      OneMapEndpoints.search('x'),
      BusrouterEndpoints.stops,
      BusrouterEndpoints.services,
      BusrouterEndpoints.routes,
      ArriveLahEndpoints.forStop('01012'),
      // Basemap tiles and the OneMap logo are fetched (flutter_map and the
      // engine decode their bytes), so they need connect-src, not img-src.
      for (final template in [
        BasemapEndpoints.defaultTiles,
        BasemapEndpoints.nightTiles,
      ])
        Uri.parse(template.replaceAll(RegExp('[{}]'), '')),
      BasemapEndpoints.logo,
    }.map((u) => '${u.scheme}://${u.host}').toSet();
    // The Flutter engine's own CDN: CanvasKit and fallback fonts.
    const engine = {'https://www.gstatic.com', 'https://fonts.gstatic.com'};

    final connect = _policy()['connect-src']!;
    expect(connect.first, "'self'");
    expect(connect.skip(1).toSet(), {...providers, ...engine});
  });

  test(
    'scripts only from the app and the CanvasKit CDN; no eval or inline',
    () {
      final script = _policy()['script-src']!;
      expect(script, containsAll(["'self'", 'https://www.gstatic.com']));
      expect(script, isNot(contains("'unsafe-eval'")));
      expect(script, isNot(contains("'unsafe-inline'")));
      // Only hash sources besides those: the debug loader's inline snippet.
      final others = script.where(
        (s) => !{
          "'self'",
          "'wasm-unsafe-eval'",
          'https://www.gstatic.com',
        }.contains(s),
      );
      expect(others, everyElement(startsWith("'sha256-")));
    },
  );

  test('no plugins, no base-URI or form-target changes', () {
    final policy = _policy();
    expect(policy['object-src'], ["'none'"]);
    expect(policy['base-uri'], ["'self'"]);
    expect(policy['form-action'], ["'none'"]);
    expect(policy['default-src'], ["'self'"]);
  });
}
