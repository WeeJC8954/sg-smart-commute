// Milestone 0 place-search feasibility evaluation (Dart VM, not shipped).
//
// Runs a representative Singapore query set against OneMap (tokenless),
// Photon and Nominatim, and writes raw results plus a summary.
//
//   dart run tool/place_search_eval.dart
//
// Respects public usage policies: Nominatim is called at most once per
// second, never for type-ahead prefixes, and identifies the app.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

const userAgent =
    'sg-smart-commute-m0-eval/0.1 (university course project; '
    'https://github.com/WeeJC8954/sg-smart-commute)';

class Case {
  const Case(
    this.category,
    this.query,
    this.expect, {
    this.postcode,
    this.prefix = false,
  });
  final String category;
  final String query;

  /// Any of these (upper-case) substrings in a result's name/address
  /// counts as the intended place.
  final List<String> expect;

  /// For postal-code / HDB address queries: the exact expected postcode.
  final String? postcode;

  /// Type-ahead prefix case (Nominatim is skipped per its policy).
  final bool prefix;
}

const cases = <Case>[
  // Postal codes
  Case('postal', '238801', ['ION ORCHARD', 'ORCHARD TURN'], postcode: '238801'),
  Case('postal', '098585', ['VIVOCITY', 'HARBOURFRONT'], postcode: '098585'),
  Case('postal', '119077', [
    'NATIONAL UNIVERSITY',
    'KENT RIDGE',
    'NUS',
  ], postcode: '119077'),
  Case('postal', '639798', ['NANYANG', 'NTU'], postcode: '639798'),
  Case('postal', '018956', [
    'MARINA BAY SANDS',
    'BAYFRONT',
  ], postcode: '018956'),
  Case('postal', '169608', [
    'SINGAPORE GENERAL HOSPITAL',
    'OUTRAM',
  ], postcode: '169608'),
  Case('postal', '560123', ['ANG MO KIO'], postcode: '560123'),
  Case('postal', '520201', ['TAMPINES'], postcode: '520201'),
  Case('postal', '760345', ['YISHUN'], postcode: '760345'),
  // HDB addresses (full and abbreviated)
  Case('hdb', '123 Ang Mo Kio Avenue 6', ['ANG MO KIO'], postcode: '560123'),
  Case('hdb', 'Blk 123 Ang Mo Kio Ave 6', ['ANG MO KIO'], postcode: '560123'),
  Case('hdb', '201 Tampines Street 21', ['TAMPINES'], postcode: '520201'),
  Case('hdb', '201 Tampines St 21', ['TAMPINES'], postcode: '520201'),
  Case('hdb', '345 Yishun Avenue 11', ['YISHUN'], postcode: '760345'),
  // Streets
  Case('street', 'Orchard Road', ['ORCHARD ROAD', 'ORCHARD RD']),
  Case('street', 'Bencoolen Street', ['BENCOOLEN']),
  Case('street', 'Upper Thomson Road', ['UPPER THOMSON']),
  Case('street', 'Jalan Besar', ['JALAN BESAR']),
  Case('street', 'Lorong Chuan', ['LORONG CHUAN']),
  // Malls
  Case('mall', 'VivoCity', ['VIVOCITY']),
  Case('mall', 'Jewel Changi Airport', ['JEWEL']),
  Case('mall', 'Northpoint City', ['NORTHPOINT']),
  Case('mall', 'Tampines Mall', ['TAMPINES MALL']),
  Case('mall', 'Junction 8', ['JUNCTION 8']),
  Case('mall', 'Causeway Point', ['CAUSEWAY POINT']),
  // Universities / institutions
  Case('university', 'NUS', ['NATIONAL UNIVERSITY OF SINGAPORE', 'KENT RIDGE']),
  Case('university', 'National University of Singapore', [
    'NATIONAL UNIVERSITY OF SINGAPORE',
    'NUS',
  ]),
  Case('university', 'NTU', [
    'NANYANG TECHNOLOGICAL',
    'NANYANG AVENUE',
    'NANYANG DRIVE',
  ]),
  Case('university', 'Singapore Management University', [
    'SINGAPORE MANAGEMENT UNIVERSITY',
    'SMU',
  ]),
  Case('university', 'SUTD', ['SINGAPORE UNIVERSITY OF TECHNOLOGY', 'SUTD']),
  Case('university', 'Singapore Polytechnic', ['SINGAPORE POLYTECHNIC']),
  // Landmarks / POIs
  Case('landmark', 'Marina Bay Sands', ['MARINA BAY SANDS']),
  Case('landmark', 'Gardens by the Bay', ['GARDENS BY THE BAY']),
  Case('landmark', 'Changi Airport Terminal 3', ['TERMINAL 3']),
  Case('landmark', 'Singapore General Hospital', [
    'SINGAPORE GENERAL HOSPITAL',
  ]),
  Case('landmark', 'Singapore Botanic Gardens', ['BOTANIC GARDENS']),
  Case('landmark', 'Merlion Park', ['MERLION']),
  Case('landmark', 'Bishan MRT', ['BISHAN']),
  // Less prominent neighbourhood locations
  Case('neighbourhood', 'Chong Pang Market', ['CHONG PANG']),
  Case('neighbourhood', 'Tiong Bahru Market', ['TIONG BAHRU']),
  Case('neighbourhood', 'Holland Village', ['HOLLAND VILLAGE', 'HOLLAND V']),
  Case('neighbourhood', 'Sembawang Park', ['SEMBAWANG PARK']),
  Case('neighbourhood', 'Bukit Panjang Plaza', ['BUKIT PANJANG PLAZA']),
  Case('neighbourhood', 'Pasir Ris Park', ['PASIR RIS PARK']),
  Case('neighbourhood', 'Kovan Hougang Market', ['KOVAN', 'HOUGANG']),
  Case('neighbourhood', 'Toa Payoh Lorong 1', [
    'TOA PAYOH LORONG 1',
    'LORONG 1 TOA PAYOH',
    'LOR 1 TOA PAYOH',
  ]),
  // Type-ahead prefixes (OneMap + Photon only)
  Case('prefix', 'vivoc', ['VIVOCITY'], prefix: true),
  Case('prefix', 'northpoi', ['NORTHPOINT'], prefix: true),
  Case('prefix', 'gardens by', ['GARDENS BY THE BAY'], prefix: true),
  Case('prefix', 'tiong bah', ['TIONG BAHRU'], prefix: true),
  // Negative
  Case('negative', '000000', [], postcode: '000000'),
];

class Hit {
  Hit(this.name, this.address, this.postcode, this.lat, this.lng);
  final String name;
  final String address;
  final String? postcode;
  final double lat;
  final double lng;
  Map<String, Object?> toJson() => {
    'name': name,
    'address': address,
    'postcode': postcode,
    'lat': lat,
    'lng': lng,
  };
}

class Outcome {
  Outcome(this.provider, this.hits, this.ms, {this.error, this.note});
  final String provider;
  final List<Hit> hits;
  final int ms;
  final String? error;
  final String? note;
}

final client = http.Client();

bool inSg(double lat, double lng) =>
    lat >= 1.15 && lat <= 1.48 && lng >= 103.6 && lng <= 104.1;

Future<Outcome> oneMap(String q) async {
  final sw = Stopwatch()..start();
  final uri = Uri.https('www.onemap.gov.sg', '/api/common/elastic/search', {
    'searchVal': q,
    'returnGeom': 'Y',
    'getAddrDetails': 'Y',
    'pageNum': '1',
  });
  try {
    final res = await client
        .get(uri, headers: {'User-Agent': userAgent})
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      return Outcome(
        'onemap',
        [],
        sw.elapsedMilliseconds,
        error: 'HTTP ${res.statusCode}',
      );
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final hits = (j['results'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(
          (r) => Hit(
            '${r['SEARCHVAL']}',
            '${r['ADDRESS']}',
            (r['POSTAL'] as String?) == 'NIL' ? null : r['POSTAL'] as String?,
            double.parse('${r['LATITUDE']}'),
            double.parse('${r['LONGITUDE']}'),
          ),
        )
        .toList();
    return Outcome(
      'onemap',
      hits,
      sw.elapsedMilliseconds,
      note: j['error'] as String?,
    );
  } catch (e) {
    return Outcome('onemap', [], sw.elapsedMilliseconds, error: '$e');
  }
}

Future<Outcome> photon(String q) async {
  final sw = Stopwatch()..start();
  final uri = Uri.https('photon.komoot.io', '/api/', {
    'q': q,
    'bbox': '103.6,1.15,104.1,1.48',
    'limit': '5',
  });
  try {
    final res = await client
        .get(uri, headers: {'User-Agent': userAgent})
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      return Outcome(
        'photon',
        [],
        sw.elapsedMilliseconds,
        error: 'HTTP ${res.statusCode}',
      );
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final hits = <Hit>[];
    for (final f in (j['features'] as List).cast<Map<String, dynamic>>()) {
      final p = f['properties'] as Map<String, dynamic>;
      if (p['countrycode'] != 'SG') continue;
      final c = (f['geometry']['coordinates'] as List).cast<num>();
      final addr = [
        p['housenumber'],
        p['street'],
        p['district'] ?? p['locality'],
        p['postcode'],
      ].where((e) => e != null).join(' ');
      // Postcode features carry the code in `name`, not `postcode`.
      final postcode = p['osm_value'] == 'postcode'
          ? p['name'] as String?
          : p['postcode'] as String?;
      hits.add(
        Hit(
          '${p['name'] ?? p['street'] ?? ''}',
          addr,
          postcode,
          c[1].toDouble(),
          c[0].toDouble(),
        ),
      );
    }
    return Outcome('photon', hits, sw.elapsedMilliseconds);
  } catch (e) {
    return Outcome('photon', [], sw.elapsedMilliseconds, error: '$e');
  }
}

DateTime _lastNominatim = DateTime.fromMillisecondsSinceEpoch(0);

Future<Outcome> nominatim(String q) async {
  final wait =
      const Duration(milliseconds: 1100) -
      DateTime.now().difference(_lastNominatim);
  if (!wait.isNegative) await Future<void>.delayed(wait);
  _lastNominatim = DateTime.now();
  final sw = Stopwatch()..start();
  final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
    'q': q,
    'countrycodes': 'sg',
    'format': 'jsonv2',
    'addressdetails': '1',
    'limit': '5',
  });
  try {
    final res = await client
        .get(uri, headers: {'User-Agent': userAgent})
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      return Outcome(
        'nominatim',
        [],
        sw.elapsedMilliseconds,
        error: 'HTTP ${res.statusCode}',
      );
    }
    final hits = (jsonDecode(res.body) as List)
        .cast<Map<String, dynamic>>()
        .map(
          (r) => Hit(
            '${r['name'] ?? ''}',
            '${r['display_name']}',
            (r['address'] as Map?)?['postcode'] as String?,
            double.parse('${r['lat']}'),
            double.parse('${r['lon']}'),
          ),
        )
        .toList();
    return Outcome('nominatim', hits, sw.elapsedMilliseconds);
  } catch (e) {
    return Outcome('nominatim', [], sw.elapsedMilliseconds, error: '$e');
  }
}

double haversineM(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1), dLng = rad(lng2 - lng1);
  final a =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) *
          math.cos(rad(lat2)) *
          math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.sqrt(a));
}

/// Index (0-based) of the first hit that is the intended place, or -1.
int matchIndex(Case c, List<Hit> hits) {
  for (var i = 0; i < hits.length; i++) {
    final h = hits[i];
    if (!inSg(h.lat, h.lng)) continue;
    // Postal-code and HDB block queries need the exact postcode: a hit on
    // the right street but the wrong block is not the intended place.
    if (c.postcode != null) {
      if (h.postcode == c.postcode) return i;
      continue;
    }
    final text = '${h.name} ${h.address}'.toUpperCase();
    // Whole-word match so 'NTU' does not match 'NTUC'.
    if (c.expect.any(
      (k) => RegExp(r'\b' + RegExp.escape(k) + r'\b').hasMatch(text),
    )) {
      return i;
    }
  }
  return -1;
}

Future<void> main() async {
  final rows = <Map<String, Object?>>[];
  final providers = ['onemap', 'photon', 'nominatim'];
  final score = {
    for (final p in providers) p: <String, List<int>>{},
  }; // category -> [top1, top3, n]

  for (final c in cases) {
    final outs = <Outcome>[await oneMap(c.query), await photon(c.query)];
    if (!c.prefix) outs.add(await nominatim(c.query));
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final matched = <String, Hit>{};
    final row = <String, Object?>{'category': c.category, 'query': c.query};
    for (final o in outs) {
      final idx = matchIndex(c, o.hits);
      if (idx >= 0) matched[o.provider] = o.hits[idx];
      final s = score[o.provider]!.putIfAbsent(c.category, () => [0, 0, 0]);
      s[2]++;
      final negativeOk = c.category == 'negative' && idx < 0;
      if (idx == 0 || negativeOk) s[0]++;
      if ((idx >= 0 && idx < 3) || negativeOk) s[1]++;
      row[o.provider] = {
        'matchIndex': idx,
        'ms': o.ms,
        'error': o.error,
        'note': o.note,
        'top': o.hits.take(3).map((h) => h.toJson()).toList(),
      };
    }
    // Agreement: distance of each provider's matched hit from OneMap's (when both matched).
    final ref = matched['onemap'];
    if (ref != null) {
      row['distFromOneMapM'] = {
        for (final e in matched.entries)
          if (e.key != 'onemap')
            e.key: haversineM(
              ref.lat,
              ref.lng,
              e.value.lat,
              e.value.lng,
            ).round(),
      };
    }
    rows.add(row);
    stdout.writeln(
      '${c.category.padRight(14)} ${c.query.padRight(36)} '
      '${outs.map((o) => '${o.provider}=${matchIndex(c, o.hits)}${o.error != null ? '(ERR ${o.error})' : ''}').join('  ')}'
      '${row['distFromOneMapM'] ?? ''}',
    );
  }

  final out = File('docs/probe-output/place-search-eval.json');
  await out.writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'runAtUtc': DateTime.now().toUtc().toIso8601String(),
      'matchRule':
          'matchIndex = first hit (0-based) inside SG bbox whose name/address contains an expected '
          'keyword; postal-code queries require exact postcode equality; HDB address queries accept exact '
          'postcode or keyword; -1 = not found in returned results. negative case passes when nothing matches.',
      'score': score,
      'rows': rows,
    }),
  );

  stdout.writeln('\nSummary (top1/top3 of n) per category:');
  final cats = cases.map((c) => c.category).toSet();
  stdout.writeln(
    'category       | ${providers.map((p) => p.padRight(12)).join('| ')}',
  );
  for (final cat in cats) {
    stdout.writeln(
      '${cat.padRight(14)} | ${providers.map((p) {
        final s = score[p]![cat];
        return (s == null ? 'n/a' : '${s[0]}/${s[1]} of ${s[2]}').padRight(12);
      }).join('| ')}',
    );
  }
  client.close();
}
