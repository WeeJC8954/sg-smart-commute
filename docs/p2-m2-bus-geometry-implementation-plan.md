# P2-M2 Bus Ride Geometry Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for
> tracking.

**Goal:** when the suggested journey is a direct bus, the P2-M1 journey map draws that ride on the road. The
line comes from busrouter `routes.min.json`, between the boarding and alighting stops the planner already
chose. If the line cannot be matched confidently, the map draws no bus line at all; it never draws a guess.

**Architecture:**

- The map **reads** the suggested `BusOption`. It never plans, and never picks another service, direction or
  stop.
- `buildMapScene` turns that option into a `MapRide`: the service, busrouter's direction index, the planner's
  boarding occurrence, and the ride's stop positions.
- After the user opens the map, `routes.min.json` is loaded once per session through the existing
  `JsonHttpClient`. A pure-Dart matcher then turns the `MapRide` plus the encoded geometry into either a
  `RideLineDrawn` (points) or a `RideLineUnavailable` (reason).
- Decoding, matching and slicing are pure Dart in `features/map/domain/`. `flutter_map` stays in
  `features/map/presentation/`.

**Tech stack:** Flutter 3.47.2 / Dart 3.13.2, Riverpod 3, flutter_map 8.3.2 (already a dependency), the
existing `JsonHttpClient`. **No new dependencies.**

**Spec / authoritative context:**

- `docs/map-feasibility.md` (§5 ride geometry, §4.2 OneMap reasonable use, §8 architecture, §10 sequence);
- `docs/architecture.md` ("Phase 2 Milestone 1");
- `docs/assumptions.md` (map rows);
- `docs/data-sources.md` (busrouter);
- `CLAUDE.md`;
- the code in `lib/features/journey/` and `lib/features/map/`.

Baseline: `main` at `c537b1f` (P2-M0 and P2-M1 merged).

---

## Global Constraints

- **No server-side component**, no proxy, no credentials. `data.busrouter.sg` is already in the CSP
  `connect-src`, so there are **no CSP policy changes**. The CSP test gains `BusrouterEndpoints.routes` in its
  provider set.
- **The journey planner is authoritative.** The map never plans and never changes the suggested service,
  direction, boarding or alighting stop. A geometry problem never changes the journey card or the plan.
- **No straight-line stand-ins for the bus ride.** This replaces P2-M0 §5 rule 2 (see Decisions).
- **Walking stays exactly as now:** P2-M1 draws no walking lines, and P2-M3 adds straight dashed "est."
  connectors. There is no walking router.
- **OneMap reasonable use (P2-M0 §4.2 / P2-M1)** stays unchanged:
  - map closed by default;
  - no tile before "Show map";
  - camera inside OneMap's bounds and z11–19, fitted once per journey without animation;
  - no prefetch;
  - no automatic tile retry.
- **`routes.min.json` is lazy:** nothing is requested before the user opens the map with a direct-bus journey.
  It is loaded at most once per session after a success. After a failure, the load is tried again only on the
  next "Show map" (a user action), never automatically.
- **Tunables** go in `lib/core/config/app_config.dart` (`MapConfig`) and `docs/assumptions.md`. They are:
  - 60 m stop-to-line tolerance;
  - 40 m candidate merge;
  - 3.0 maximum detour;
  - 50 m minimum straight hop before the detour cap applies.
- **Parsing:** busrouter JSON is parsed only in `lib/features/*/data/`. Stops are `[lng, lat, name, road]`.
  The new routes file is `{ "<service>": ["<encoded dir 0>", "<encoded dir 1>"?] }`.
- **The Web-safe decoder is mandatory:** negative deltas as `-(result >> 1) - 1`, never `~(result >> 1)`.
  dart2js bitwise operators are unsigned 32-bit.
- **Tests never call live APIs.** Real payloads are captured once into `test/fixtures/`.
- **Evidence rule:** every gate result goes in `docs/testing.md` with its real result. Anything not run is
  logged as **Not run** with the reason.
- **Out of scope:**
  - transfers;
  - choosing an alternative option from the map (P2-M3 does option sync);
  - walking routing;
  - automatic OSM fallback;
  - map-based planning;
  - live vehicles;
  - route editing;
  - the `docs/simplification-plan.md` refactor;
  - any P2-M3 work.

## Review Focus

These inputs are the most likely to bite a real user. Each one has a test in the task that owns the code.

1. **The same boarding stop appears twice in a direction** (loops and repeated stops, e.g. 11/0 has 80199 at
   indices 6 and 17). The line must follow the occurrence the planner used, not the first one in the list.
   **Task 3** exposes `boardIndex`. **Task 4** tests that 6→8 is 1,088 m and 17→19 is 306 m.
2. **The user changes destination while `routes.min.json` is still loading**, or while an old line is shown.
   The old ride's line must never appear on the new journey. **Task 7**: a hold/release widget test, plus the
   `RideLineDrawn.ride == scene.ride` guard.
3. **The geometry loads after a failure on a flaky network.** No automatic retry, but the next "Show map" tries
   again. Markers and the journey card are unaffected throughout. **Task 6**: a fail → hide → show → succeed
   test.
4. **busrouter drops or reorders a direction**, so the planner's direction index no longer matches the routes
   file's index. A wrong polyline must not be drawn. **Task 3** keeps the source direction index. This
   index mapping is the safeguard (the matcher does not detect a swapped direction); a scene test pins it.
5. **A walk-only, no-bus or no-nearby-stop journey with the map open** must not request `routes.min.json`.
   **Task 6**: load count stays 0.

---

## Decisions (re-evaluated for P2-M2)

### D1. Unmatched geometry: markers only, no straight line (replaces P2-M0 §5 rule 2)

P2-M0 proposed straight dashed connectors for unmatched hops, labelled "route shape approximate". That is
**rejected**, at the user's request, because a straight line between two stops looks like a route.

**Rule:** a ride's line is drawn only if **every** stop of the ride, from boarding to alighting, matches the
geometry in order, within tolerance, and no hop exceeds the detour cap. Otherwise:

- the map shows no bus line;
- the boarding and alighting markers stay;
- a short note appears below the map: *"The bus route line isn't available for this ride. The stops are
  shown."*

This is a **degraded visualisation, not a routing failure**. The journey card, the plan and arrivals do not
change, and nothing on the card mentions it.

Measured cost of all-or-nothing on live data, 2026-10-03: **88.0%** of random rides are still drawn (D2), so
roughly 1 in 8 rides shows markers only.

### D2. Simplify the P2-M0 probe algorithm; do not copy it

`tool/route_geometry_probe.dart` is evidence code. It answers a different question: how much of every whole
direction can be matched, letting stops be skipped. Its cost and its outputs suit that question, not
production. It:

- matches all stops of a whole direction;
- allows skipped stops;
- runs an O(n² · c) dynamic programme over every earlier state;
- tries four orientations per direction;
- reports a per-direction map.

**The production matcher solves the narrower problem:**

- **Input:** only the ride's stops, from boarding to alighting (typically 2–40 points).
- **All of them must match** (D1), so there is no skipping. Each dynamic-programme step looks only at the
  previous stop's candidates, which is O(n · c²).
- **Objective:** the in-order chain with the **least total along-line length**. On a road the bus runs both
  ways, this picks the tight, correct pass, not one that loops away and back.
- **Kept from the probe** (each backed by its evidence):
  - the 60 m tolerance;
  - the 40 m candidate merge (one candidate per pass of the line);
  - variants in the order: given → reversed → doubled → reversed+doubled. Reversed is for directions stored
    backwards. Doubled lines are for loops whose geometry starts at another stop, and are tried **only when the
    line is closed** (its two ends are within the 60 m tolerance). On an open line, doubling adds a straight
    joining segment from its end back to its start. A stop matched on that segment would draw a straight
    stand-in, which D1 forbids.
  - the 3× detour cap per hop, applied when the straight hop is longer than 50 m.
- **Output:** the decoded line sliced between the matched boarding and alighting positions. The two ends are
  interpolated onto the line.

**Evidence** (scratch evaluation of exactly this algorithm on live busrouter data, 2026-10-03 04:19 UTC; same
random rides as the probe, seed 1, 1–25 stops, 10 per direction):

| | P2-M0 probe (all hops drawable) | Ride matcher, doubling any line | **Ride matcher, doubling closed lines only (chosen)** |
|---|---|---|---|
| Random rides drawn | 7,036 / 7,980 (88.2%) | 7,164 / 7,980 (89.8%) | **7,020 / 7,980 (88.0%)** |
| Variants used | n/a | given 6,854, doubled 176, reversed 132, reversed+doubled 2 | given 6,854, reversed 132, doubled 34 |
| Bus 10, 03019 → 14141 | drawable, 4,426 m | drawn, 4,426 m | **drawn, direction 0, 9 stops, 4,426 m (given)** |

- **The probe also doubled open lines**, and so did the first version of this matcher. Of the 176 rides drawn
  through doubling, 142 were on open lines, where the match used the artificial joining segment: a straight
  stand-in. The closed-only rule removes exactly those. 183 of 798 directions are closed.
- **The result is the same share of rides as the probe** (88.0% against 88.2%), with a much simpler,
  ride-local algorithm and no straight stand-ins.
- The probe stays in `tool/` unchanged, as P2-M0 evidence.

### D3. The planner exposes which occurrence it boarded (`BusOption.boardIndex`)

`planDirectBus` already knows the boarding occurrence `i` in the direction's stop list. `BusOption` does not
keep it; it keeps only `board`, `alight` and `stops = j − i`. Re-deriving `i` in the map would duplicate
planner logic, and in loops or repeated stops it could choose another occurrence.

Fix: add `final int boardIndex` to `BusOption`, set from `i`. This is one constructor call in
`direct_bus_planner.dart` (the only one in the repository). No behaviour changes: the ranking does not look at
it.

### D4. Keep busrouter's direction index (`BusService.sourceDirectionOf`)

`parseBusrouterServices` drops a direction that has fewer than 2 known stops. That would shift
`BusService.directions` against `routes.min.json`, which has one polyline per busrouter direction.

Live data today: 0 unknown stop codes, 0 dropped directions, and equal direction counts for all 602 services.
The shift is therefore latent, but a wrong polyline must never be drawn.

Fix:

- `BusService` gains an optional `sourceDirections` list, set by the parser **only** when it drops something.
- `sourceDirectionOf(d)` returns `sourceDirections?[d] ?? d`.
- The index mapping is what prevents the wrong direction's line. The matcher does not detect a swapped
  direction (its reversed variant may accept it), so the mapping is pinned by a scene test.

### D5. Fit the camera to the ride's stops as well

`MapScene.bounds` adds every ride stop position to the four markers. These positions are known synchronously
from the bus network the plan came from. The camera is therefore still fitted **once per journey, before the
first frame** (the P2-M1 rule), and a bending ride stays in view. There is no refit when the line arrives.

### D6. Where things live

- **`features/map/domain/`** (pure Dart):
  - `polyline_codec.dart`;
  - `ride_geometry.dart` (`MapRide`, `RideLine`, `matchRide`);
  - `route_geometry.dart` (`RouteGeometry`, repository interface);
  - `map_scene.dart` (`MapRide` on the scene).
- **`features/map/data/`:** the busrouter routes parser and repository.
- **`features/map/map_providers.dart`:** `routeGeometryProvider` and `rideLineProvider`.
- **`features/map/presentation/journey_map.dart`:** a `PolylineLayer` and the note.
- `routes.min.json` belongs to the map, not the planner. The journey feature never imports
  `features/map`, and the dependency stays one-way: map reads journey.

---

## Baseline facts the implementer needs

- **`routes.min.json`:** `https://data.busrouter.sg/v1/routes.min.json`, about 289 KB, `ACAO: *`,
  `max-age=86400`. A JSON object mapping service number to a list of 1–2 strings. Each string is a
  **precision-5 Google encoded polyline**, one per direction, in the same order as `services.min.json`
  `routes`. The services correspond 1:1 (602 services, 798 directions).
- **`services.min.json`:** `{ "<n>": { "name": "...", "routes": [[codes…], [codes…]?] } }`. It is parsed into
  `BusService.directions` by `lib/features/journey/data/busrouter_parser.dart`.
- **`JsonHttpClient`** (`lib/core/http/json_http_client.dart`):
  - 10 s timeout;
  - 2 retries on 5xx or network errors, none on 4xx;
  - 429 → `ApiRateLimited` with a host hold;
  - in-flight deduplication;
  - 4 MiB body cap (`routes.min.json` is far below it).

  busrouter has no client-side rate limiter (it isn't data.gov.sg or OneMap), and this one file per session
  needs none.
- **Session-cache pattern to copy:** `BusrouterRepository` (`lib/features/journey/data/busrouter_repository.dart`).
  It is lazy, shares one in-flight load, keeps a success for the session, and does not keep a failure. It wraps
  failures as `StaticDataUnavailable(StaticDataset.…)`.
- **Live test cases** (measured 2026-10-03 with the D2 algorithm). They are captured into fixtures in Task 1.

  | Case | Service/direction | Ride (boardIndex → alight index) | Codes | Expected |
  |---|---|---|---|---|
  | Normal (given) | 10/0 | index of 03019 → +9 | 03019 → 14141 | drawn, 4,426 m ± 5 |
  | Closed loop whose geometry starts at another stop (doubled) | 115/0 | 0 → 1 | 63221 → 63231 | drawn, 325 m ± 5 |
  | Open line that does not reach the first stop (doubling would only match through the artificial join) | 10/1 | 0 → 1 | 16009 → 16089 | unavailable (`notMatched`) |
  | Reversed geometry | 46/1 | 0 → 1 | 77009 → 77321 | drawn, 65 m ± 5 |
  | Loop service (first == last stop) | 4/0 | 0 → 1 | 75009 → 76191 | drawn, 499 m ± 5 |
  | Repeated stop, first occurrence | 11/0 | 6 → 8 | 80199 → 90039 | drawn, 1,088 m ± 5 |
  | Repeated stop, second occurrence | 11/0 | 17 → 19 | 80199 → 80171 | drawn, 306 m ± 5 |
  | Mismatched geometry | 2B/0 | 0 → 3 | 99009 → 99039 | unavailable (`notMatched`) |

  "± 5 m" covers floating-point differences between the scratch Python and the Dart port.

---

## File-by-file change list

| File | Change |
|---|---|
| `tool/capture_route_geometry_fixtures.dart` | **Create.** Dev-only: downloads the three busrouter files once and writes the fixture subset |
| `test/fixtures/busrouter/geometry/routes.json` | **Create** (captured). `routes.min.json` entries for 10, 46, 4, 11, 2B |
| `test/fixtures/busrouter/geometry/services.json` | **Create** (captured). `services.min.json` entries for the same services |
| `test/fixtures/busrouter/geometry/stops.json` | **Create** (captured). Every stop those services use |
| `lib/core/config/app_config.dart` | **Modify.** `BusrouterEndpoints.routes`; `MapConfig.rideStopToleranceMeters`, `rideCandidateMergeMeters`, `rideMaxDetour`, `rideDetourMinStraightMeters` |
| `lib/core/errors/app_failure.dart` | **Modify.** `StaticDataset.busRouteGeometry` + its message |
| `lib/features/journey/domain/bus_network.dart` | **Modify.** `BusService.sourceDirections` + `sourceDirectionOf` (D4) |
| `lib/features/journey/data/busrouter_parser.dart` | **Modify.** Record source direction indices when a direction is dropped (D4) |
| `lib/features/journey/domain/direct_bus_planner.dart` | **Modify.** `BusOption.boardIndex` (D3) |
| `lib/features/map/domain/polyline_codec.dart` | **Create.** `decodePolyline` (Web-safe, throws `FormatException`) |
| `lib/features/map/domain/route_geometry.dart` | **Create.** `RouteGeometry`, `RouteGeometryRepository` |
| `lib/features/map/domain/ride_geometry.dart` | **Create.** `MapRide`, `RideLine` (`RideLineDrawn` / `RideLineUnavailable`), `RideLineGap`, `RideMatchConfig`, `matchRide` |
| `lib/features/map/domain/map_scene.dart` | **Modify.** `MapScene.ride`; `buildMapScene(stops:)`; bounds include ride stops; equality |
| `lib/features/map/data/busrouter_routes_parser.dart` | **Create.** `parseBusrouterRoutes` |
| `lib/features/map/data/busrouter_route_geometry_repository.dart` | **Create.** Lazy, session-cached repository |
| `lib/features/map/map_providers.dart` | **Modify.** `mapSceneProvider` passes stops; `routeGeometryRepositoryProvider`, `routeGeometryProvider`, `rideLineProvider`; `MapExpanded.show` retries a failed load |
| `lib/features/map/presentation/journey_map.dart` | **Modify.** `PolylineLayer` (only for this scene's ride), the "line isn't available" note |
| `integration_test/fakes/fake_route_geometry.dart` | **Create.** `encodePolyline` (Web-safe) + `FakeRouteGeometryRepository` built from the fake bus network |
| `integration_test/fakes/test_app.dart` | **Modify.** `routeGeometry` parameter; default fake |
| `integration_test/happy_path_test.dart` | **Modify.** After "Show map", the ride line is drawn |
| `test/features/map/polyline_codec_test.dart` | **Create.** Also run with `--platform chrome` |
| `test/features/map/ride_geometry_test.dart` | **Create.** Fixture cases + synthetic cases |
| `test/features/map/busrouter_routes_test.dart` | **Create.** Parser + repository |
| `test/features/map/map_scene_test.dart` | **Modify.** `MapRide` construction, bounds, equality |
| `test/features/map/journey_map_card_test.dart` | **Modify.** Line, note, lazy load, one load, retry on show, stale guard |
| `test/features/journey/planner_test.dart` (existing planner test file; find it with `grep -l planDirectBus test/features/journey`) | **Modify.** `boardIndex` on a repeated-stop network |
| `test/features/journey/busrouter_test.dart` | **Modify.** `sourceDirectionOf` when a direction is dropped |
| `test/core/app_failure_test.dart` | **Modify.** New `StaticDataset` message |
| `test/web/content_security_policy_test.dart` | **Modify.** Add `BusrouterEndpoints.routes` |
| `docs/map-feasibility.md`, `docs/assumptions.md`, `docs/architecture.md`, `docs/data-sources.md`, `docs/testing.md`, `CLAUDE.md` | **Modify** (Task 8) |

---

## Domain interfaces (all pure Dart; no Flutter, no flutter_map)

```dart
// lib/features/map/domain/route_geometry.dart
/// busrouter routes.min.json: one encoded polyline per service direction, in
/// busrouter's direction order. Decoded only when a ride needs it.
class RouteGeometry {
  const RouteGeometry(this._encoded);
  final Map<String, List<String>> _encoded;

  /// The encoded polyline for [service]'s busrouter direction [direction],
  /// or null when the file has none.
  String? encoded(String service, int direction) {
    final list = _encoded[service];
    if (list == null || direction < 0 || direction >= list.length) return null;
    return list[direction];
  }

  int get serviceCount => _encoded.length;
}

abstract interface class RouteGeometryRepository {
  /// The whole file, loaded once per session. Throws
  /// `StaticDataUnavailable(StaticDataset.busRouteGeometry)`.
  Future<RouteGeometry> load();
}
```

```dart
// lib/features/map/domain/ride_geometry.dart (public surface)
class MapRide {            // the ride the planner chose; value equality
  const MapRide({required this.service, required this.sourceDirection,
      required this.boardIndex, required this.stops});
  final String service;        // e.g. '10'
  final int sourceDirection;   // busrouter direction index (D4)
  final int boardIndex;        // the planner's boarding occurrence (D3)
  final List<LatLng> stops;    // boarding … alighting positions, in order
}

enum RideLineGap { noGeometry, malformedGeometry, notMatched }

sealed class RideLine { const RideLine(this.ride); final MapRide ride; }
final class RideLineDrawn extends RideLine {
  const RideLineDrawn(super.ride, this.points);
  final List<LatLng> points;   // ≥ 2, boarding end first
}
final class RideLineUnavailable extends RideLine {
  const RideLineUnavailable(super.ride, this.gap);
  final RideLineGap gap;
}

class RideMatchConfig { /* defaults from MapConfig; see Task 4 */ }

RideLine matchRide(MapRide ride, RouteGeometry geometry,
    {RideMatchConfig config = const RideMatchConfig()});
```

```dart
// lib/features/map/domain/polyline_codec.dart
List<LatLng> decodePolyline(String encoded); // throws FormatException
```

```dart
// map_scene.dart additions
class MapScene {
  const MapScene(this.markers, {this.serviceNumber, this.ride});
  final MapRide? ride;  // null unless the suggested option is a direct bus
  // bounds: markers + ride.stops; == / hashCode include ride
}

MapScene buildMapScene({required LatLng origin, required String originLabel,
    required LatLng destination, required String destinationLabel,
    JourneyPlan? plan, Map<String, BusStop>? stops});
```

```dart
// map_providers.dart additions
final routeGeometryRepositoryProvider = Provider<RouteGeometryRepository>(...);
final routeGeometryProvider = FutureProvider<RouteGeometry>(...);  // session-held
/// Null when the scene has no ride. Watched only by JourneyMap, which exists
/// only while the map is open, so the file is never requested before
/// "Show map".
final rideLineProvider = Provider<AsyncValue<RideLine>?>(...);
```

## Failure behaviour

| Situation | Map | Journey card / plan | Note shown |
|---|---|---|---|
| Map closed | nothing built | unchanged | — |
| Walk-only / no direct bus / no nearby stops | origin + destination markers; **no request** for `routes.min.json` | unchanged | — |
| Direct bus, geometry loading | four markers, no line | unchanged | — (no spinner: the markers are the answer) |
| Geometry loaded, ride matched | four markers + ride line | unchanged | — |
| Service or direction missing from the file | markers, no line | unchanged | "The bus route line isn't available for this ride. The stops are shown." |
| Malformed polyline (decode throws, or fewer than 2 points) | markers, no line | unchanged | same note |
| A stop more than 60 m from the line, out of order, or a hop over 3× its straight line, in every variant | markers, no line | unchanged | same note |
| `routes.min.json` failed (network, HTTP, 429, too large, not JSON, schema) | markers, no line; the failure is **not** cached; the next "Show map" tries once more | unchanged | same note |
| Journey changes while open or loading | the line is recomputed for the new ride; an older ride's line is never drawn (`RideLineDrawn.ride == scene.ride`) | unchanged | — |
| Tiles fail (P2-M1) | unchanged P2-M1 behaviour; the line and markers still draw | unchanged | P2-M1 tiles note |

The note is one line below the map (key `map-ride-unavailable`, a live region). It appears together with the
P2-M1 tiles note when both apply. There is no Retry button: reopening the map is the retry.

---

## Tasks (test-first; one commit each unless noted)

Work on a feature branch from up-to-date `origin/main`, e.g. `feat/p2-m2-bus-geometry` (CLAUDE.md: never on
`main`). Run `dart format .` before each commit.

### Task 1: Capture the geometry fixtures

**Files:**

- Create: `tool/capture_route_geometry_fixtures.dart`
- Create (output): `test/fixtures/busrouter/geometry/{routes,services,stops}.json`

**Interfaces:**

- Produces: three fixture files keyed exactly as the live files (subset). Later tasks load them with
  `jsonDecode(File(...).readAsStringSync())`.

- [ ] **Step 1: Write the tool.**

```dart
// Dev-only (not shipped): downloads busrouter's routes/services/stops once
// and writes the P2-M2 geometry fixture subset. Run:
//   dart run tool/capture_route_geometry_fixtures.dart
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const services = ['10', '46', '4', '11', '2B', '115'];
const base = 'https://data.busrouter.sg/v1';
const out = 'test/fixtures/busrouter/geometry';

Future<void> main() async {
  Future<Map<String, dynamic>> get(String name) async {
    final r = await http.get(Uri.parse('$base/$name.min.json'));
    if (r.statusCode != 200) throw StateError('$name: HTTP ${r.statusCode}');
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  final routes = await get('routes');
  final svc = await get('services');
  final stops = await get('stops');
  final codes = <String>{
    for (final s in services)
      for (final dir in (svc[s] as Map)['routes'] as List)
        ...(dir as List).cast<String>(),
  };
  const encoder = JsonEncoder.withIndent(' ');
  Directory(out).createSync(recursive: true);
  File('$out/routes.json').writeAsStringSync(
    encoder.convert({for (final s in services) s: routes[s]}),
  );
  File('$out/services.json').writeAsStringSync(
    encoder.convert({for (final s in services) s: svc[s]}),
  );
  File('$out/stops.json').writeAsStringSync(
    encoder.convert({for (final c in codes.toList()..sort()) c: stops[c]}),
  );
  stdout.writeln(
    'wrote ${services.length} services, ${codes.length} stops '
    '(${DateTime.now().toUtc().toIso8601String()})',
  );
}
```

- [ ] **Step 2: Run it once.** `dart run tool/capture_route_geometry_fixtures.dart`. Expected: `wrote 6
  services, N stops (…)`.
- [ ] **Step 3: Sanity-check.** `services.json` must contain `10`, and `10/0` must contain `03019` then
  `14141` with 9 stops between their indices. Record the capture time for the Task 8 run log.
- [ ] **Step 4: Commit.**
  `git add tool/capture_route_geometry_fixtures.dart test/fixtures/busrouter/geometry && git commit -m "test(p2-m2): capture busrouter route geometry fixtures"`

### Task 2: Web-safe polyline decoder

**Files:**

- Create: `lib/features/map/domain/polyline_codec.dart`
- Test: `test/features/map/polyline_codec_test.dart`

**Interfaces:**

- Produces: `List<LatLng> decodePolyline(String encoded)`. It throws `FormatException` on malformed input.
  Precision 5.

- [ ] **Step 1: Write the failing tests.**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/core/geo/geo.dart';
import 'package:sg_smart_commute/features/map/domain/polyline_codec.dart';

void main() {
  test('Google reference polyline: positive and negative deltas', () {
    // https://developers.google.com/maps/documentation/utilities/polylinealgorithm
    final points = decodePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@');
    expect(points.length, 3);
    void near(LatLng p, double lat, double lng) {
      expect(p.latitude, closeTo(lat, 1e-9));
      expect(p.longitude, closeTo(lng, 1e-9));
    }
    near(points[0], 38.5, -120.2);
    near(points[1], 40.7, -120.95); // negative longitude delta
    near(points[2], 43.252, -126.453);
  });

  test('a large negative delta is decoded exactly '
      '(would be ~2^32 off with ~(r >> 1) under dart2js)', () {
    // (1.3, 103.8) then (1.25, 103.75): deltas -5000 / -5000 in 1e-5 units.
    final points = decodePolyline('_||F_mpxRnwHnwH');
    expect(points[0].latitude, closeTo(1.3, 1e-9));
    expect(points[0].longitude, closeTo(103.8, 1e-9));
    expect(points[1].latitude, closeTo(1.25, 1e-9));
    expect(points[1].longitude, closeTo(103.75, 1e-9));
  });

  test('empty string decodes to no points', () {
    expect(decodePolyline(''), isEmpty);
  });

  for (final (why, s) in [
    ('truncated (continuation bit at the end)', '_p~iF~ps|U_'),
    ('a latitude without a longitude', '_p~iF'),
    ('a character below "?"', '_p~iF~ps|U ' ),
    ('a value longer than 32 bits', '~~~~~~~~~~'),
  ]) {
    test('malformed: $why → FormatException', () {
      expect(() => decodePolyline(s), throwsFormatException);
    });
  }
}
```

The literals were computed with the Task 7 encoder, which reproduces Google's reference string exactly, and
they decode back to the stated points. If one ever disagrees, fix the decoder, not the literal.

- [ ] **Step 2: Run, expect failure.** `flutter test test/features/map/polyline_codec_test.dart`. Expected: it
  fails to compile (`decodePolyline` is undefined).
- [ ] **Step 3: Implement.**

```dart
import '../../../core/geo/geo.dart';

/// Decodes a precision-5 Google encoded polyline (busrouter
/// routes.min.json). Throws [FormatException] when [encoded] is malformed.
///
/// Web-safe: dart2js bitwise operators are unsigned 32-bit, so a negative
/// delta is `-(result >> 1) - 1`, never `~(result >> 1)` (which turns every
/// negative delta into about +2^32 on the Web; found in the P2-M0 spike).
List<LatLng> decodePolyline(String encoded) {
  final points = <LatLng>[];
  var index = 0, lat = 0, lng = 0;

  int next() {
    var shift = 0, result = 0;
    while (true) {
      if (index >= encoded.length) {
        throw FormatException('truncated polyline', encoded, index);
      }
      final chunk = encoded.codeUnitAt(index++) - 63;
      if (chunk < 0 || chunk > 63) {
        throw FormatException('invalid polyline character', encoded, index - 1);
      }
      result |= (chunk & 0x1f) << shift;
      if (chunk < 0x20) break;
      shift += 5;
      if (shift > 25) {
        throw FormatException('polyline value too long', encoded, index);
      }
    }
    return (result & 1) != 0 ? -(result >> 1) - 1 : result >> 1;
  }

  while (index < encoded.length) {
    lat += next();
    if (index >= encoded.length) {
      throw FormatException('latitude without longitude', encoded, index);
    }
    lng += next();
    points.add(LatLng(lat / 1e5, lng / 1e5));
  }
  return points;
}
```

- [ ] **Step 4: Run on the VM and on Chrome.**
  - VM: `flutter test test/features/map/polyline_codec_test.dart`. Expected: all pass.
  - Chrome: `flutter test --platform chrome test/features/map/polyline_codec_test.dart`. Expected: all pass.
    This is the run that proves the Web-safe branch.

  If Chrome cannot run here, log the Chrome run as **Not run** with the reason. Do not skip it silently.
- [ ] **Step 5: Mutation check.** Temporarily change the return to `~(result >> 1)` and re-run on Chrome.
  Expected: the large-negative-delta test fails. Restore the code, and check `git diff` is empty for the file.
- [ ] **Step 6: Commit.**
  `git commit -m "feat(map): Web-safe precision-5 polyline decoder"`

### Task 3: Planner and parser expose what the map needs (no behaviour change)

**Files:**

- Modify: `lib/features/journey/domain/direct_bus_planner.dart`
- Modify: `lib/features/journey/domain/bus_network.dart`
- Modify: `lib/features/journey/data/busrouter_parser.dart`
- Test: the existing planner test file and `test/features/journey/busrouter_test.dart`

**Interfaces:**

- Produces:
  - `BusOption.boardIndex` (int): the index in `service.directions[direction]` where the ride boards. The
    invariant is `directions[direction][boardIndex] == board.code` and
    `directions[direction][boardIndex + stops] == alight.code`.
  - `BusService.sourceDirectionOf(int direction) → int`: busrouter's direction index.

- [ ] **Step 1: Failing planner test.** Use a network where the boarding stop appears twice. The test checks
  the invariant for **every** option, and pins the expected occurrence.

```dart
test('boardIndex is the occurrence the planner rode from', () {
  BusStop s(String c, double lat, double lng) =>
      BusStop(code: c, position: LatLng(lat, lng), name: c, road: 'R');
  final stops = [
    s('A', 1.3000, 103.8000), s('B', 1.3050, 103.8050),
    s('C', 1.3100, 103.8100), s('D', 1.3500, 103.8500),
  ];
  // Loop visiting A twice; the shortest ride to D boards at the second A.
  final network = BusNetwork(
    stops: {for (final x in stops) x.code: x},
    services: {
      'L1': const BusService(number: 'L1', name: 'Loop', directions: [
        ['A', 'B', 'C', 'A', 'D'],
      ]),
    },
  );
  final plan = planDirectBus(
    network, const LatLng(1.3001, 103.8001), const LatLng(1.3501, 103.8501));
  final option = (plan as DirectBusOptions).options.single;
  final route = option.service.directions[option.direction];
  expect(option.boardIndex, 3);
  expect(route[option.boardIndex], option.board.code);
  expect(route[option.boardIndex + option.stops], option.alight.code);
});
```

- [ ] **Step 2: Failing parser test.** Drop a direction and check the source index survives.

```dart
test('a dropped direction keeps the source index of the next one', () {
  final stops = parseBusrouterStops({
    '11111': [103.8, 1.30, 'One', 'Rd'], '22222': [103.81, 1.31, 'Two', 'Rd'],
  });
  final services = parseBusrouterServices({
    'X': {'name': 'X', 'routes': [['99999', '88888'], ['11111', '22222']]},
    // …plus enough valid services that the 5 % invalid share is not hit
  }, stops);
  final x = services['X']!;
  expect(x.directions, [['11111', '22222']]);
  expect(x.sourceDirectionOf(0), 1);
});
```

Pad the input with valid services until X's dropped direction is under the invalid-share threshold. A dropped
**direction** does not count as an invalid service, but X must still parse.

- [ ] **Step 3: Run both and see them fail.**
- [ ] **Step 4: Implement.**
  - **`bus_network.dart`:** add an optional field:

    ```dart
    const BusService({required this.number, required this.name,
        required this.directions, this.sourceDirections});
    /// busrouter direction index for each kept direction; null when none
    /// was dropped (then the index is the same).
    final List<int>? sourceDirections;
    int sourceDirectionOf(int direction) =>
        sourceDirections?[direction] ?? direction;
    ```

  - **`busrouter_parser.dart` (`_service`):** track the indices while building `directions`:

    ```dart
    final directions = <List<String>>[];
    final source = <int>[];
    for (var d = 0; d < routes.length; d++) {
      final route = routes[d];
      if (route is! List || route.any((c) => c is! String)) return null;
      final known = [for (final c in route.cast<String>()) if (stops.containsKey(c)) c];
      if (known.length >= 2) { directions.add(known); source.add(d); }
    }
    if (directions.isEmpty) return null;
    final aligned = source.length == routes.length;
    return BusService(number: number, name: name, directions: directions,
        sourceDirections: aligned ? null : source);
    ```

    Unknown codes are still removed **inside** a direction. That's safe: the matcher works on positions, not
    indices. `boardIndex` refers to the filtered list, which is the same list the map reads.
  - **`direct_bus_planner.dart`:** add `required this.boardIndex` with a doc comment
    (`final int boardIndex; /// index of [board] in service.directions[direction]`). Pass `i` from
    `_attempt` through `_option`: add an `int boardIndex` parameter and call `_option(service, dir, route, o,
    d, i, j - i, network, config)`. Add `boardIndex` to `toString`.
- [ ] **Step 5: Run.**
  - `flutter test test/features/journey`. Expected: all pass, and every existing planner test is unchanged.
  - `flutter test`. Expected: all pass. `boardIndex` is not used in ranking, so no answer changes.
- [ ] **Step 6: Commit.**
  `git commit -m "feat(journey): expose the boarding occurrence and busrouter direction index"`

### Task 4: The ride matcher (pure Dart)

**Files:**

- Create: `lib/features/map/domain/route_geometry.dart`
- Create: `lib/features/map/domain/ride_geometry.dart`
- Modify: `lib/core/config/app_config.dart` (`MapConfig` ride tunables)
- Test: `test/features/map/ride_geometry_test.dart`

**Interfaces:**

- Consumes: `decodePolyline` (Task 2) and `haversineMeters` (`lib/core/geo/geo.dart`).
- Produces: `RouteGeometry`, `RouteGeometryRepository`, `MapRide`, `RideLine`, `RideLineDrawn`,
  `RideLineUnavailable`, `RideLineGap`, `RideMatchConfig` and `matchRide`, as in "Domain interfaces".

- [ ] **Step 1: Add the tunables** to `MapConfig` in `app_config.dart`:

```dart
  /// Bus ride line (P2-M2; docs/assumptions.md "Bus ride line"): a ride stop
  /// matches the route line within this distance.
  static const double rideStopToleranceMeters = 60;

  /// Positions of one stop closer than this along the line are one pass.
  static const double rideCandidateMergeMeters = 40;

  /// A hop longer than this × its straight line is not trusted…
  static const double rideMaxDetour = 3.0;

  /// …when the straight line is longer than this (very short hops are noisy).
  static const double rideDetourMinStraightMeters = 50;
```

- [ ] **Step 2: Write the failing tests.** Use the fixture cases from the table, plus synthetic lines for the
  edge cases.

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/core/geo/geo.dart';
import 'package:sg_smart_commute/features/map/domain/ride_geometry.dart';
import 'package:sg_smart_commute/features/map/domain/route_geometry.dart';

Map<String, dynamic> _fixture(String name) => jsonDecode(
  File('test/fixtures/busrouter/geometry/$name.json').readAsStringSync(),
) as Map<String, dynamic>;

final _routes = _fixture('routes');
final _services = _fixture('services');
final _stops = _fixture('stops');

RouteGeometry get geometry => RouteGeometry({
  for (final e in _routes.entries) e.key: (e.value as List).cast<String>(),
});

LatLng stopAt(String code) {
  final s = _stops[code] as List; // [lng, lat, name, road]
  return LatLng((s[1] as num).toDouble(), (s[0] as num).toDouble());
}

/// The planner's view of a ride: [from]..[to] of the direction's stop list.
MapRide ride(String service, int direction, int from, int to) {
  final codes = (((_services[service] as Map)['routes'] as List)[direction]
          as List)
      .cast<String>();
  return MapRide(
    service: service,
    sourceDirection: direction,
    boardIndex: from,
    stops: [for (final c in codes.sublist(from, to + 1)) stopAt(c)],
  );
}

int indexIn(String service, int direction, String code) =>
    ((((_services[service] as Map)['routes'] as List)[direction]) as List)
        .indexOf(code);

double lengthOf(List<LatLng> points) {
  var m = 0.0;
  for (var i = 0; i + 1 < points.length; i++) {
    m += haversineMeters(points[i], points[i + 1]);
  }
  return m;
}

void expectDrawn(RideLine line, MapRide r, double meters) {
  expect(line, isA<RideLineDrawn>(), reason: '$line');
  final points = (line as RideLineDrawn).points;
  expect(line.ride, r);
  expect(lengthOf(points), closeTo(meters, 5));
  // Starts at the boarding stop and ends at the alighting stop (on the line).
  expect(haversineMeters(points.first, r.stops.first), lessThanOrEqualTo(60));
  expect(haversineMeters(points.last, r.stops.last), lessThanOrEqualTo(60));
}

void main() {
  test('Bus 10, 03019 → 14141 (M3 smoke ride): drawn, 4,426 m', () {
    final from = indexIn('10', 0, '03019');
    final r = ride('10', 0, from, from + 9);
    expect(r.stops.length, 10);
    expectDrawn(matchRide(r, geometry), r, 4426);
  });

  test('normal direction, geometry as given: 4/0 loop service 0 → 1', () {
    final r = ride('4', 0, 0, 1);
    expectDrawn(matchRide(r, geometry), r, 499);
  });

  test('closed loop whose geometry starts at another stop (doubled): '
      '115/0 0 → 1', () {
    final r = ride('115', 0, 0, 1);
    expectDrawn(matchRide(r, geometry), r, 325);
  });

  test('an open line is never doubled: 10/1 0 → 1 → notMatched '
      '(only the artificial join would match, a straight stand-in)', () {
    final line = matchRide(ride('10', 1, 0, 1), geometry);
    expect((line as RideLineUnavailable).gap, RideLineGap.notMatched);
  });

  test('geometry stored reversed: 46/1 0 → 1', () {
    final r = ride('46', 1, 0, 1);
    expectDrawn(matchRide(r, geometry), r, 65);
  });

  test('repeated stop: each occurrence gives its own slice', () {
    final first = ride('11', 0, 6, 8), second = ride('11', 0, 17, 19);
    expect(first.stops.first, second.stops.first); // both board at 80199
    expectDrawn(matchRide(first, geometry), first, 1088);
    expectDrawn(matchRide(second, geometry), second, 306);
  });

  test('geometry that does not fit the ride: markers only (2B/0 0 → 3)', () {
    final line = matchRide(ride('2B', 0, 0, 3), geometry);
    expect((line as RideLineUnavailable).gap, RideLineGap.notMatched);
  });

  test('missing service or direction → noGeometry', () {
    final r = ride('10', 0, 0, 1);
    final noService = MapRide(service: 'NOPE', sourceDirection: 0,
        boardIndex: 0, stops: r.stops);
    final noDirection = MapRide(service: '10', sourceDirection: 5,
        boardIndex: 0, stops: r.stops);
    for (final x in [noService, noDirection]) {
      expect((matchRide(x, geometry) as RideLineUnavailable).gap,
          RideLineGap.noGeometry);
    }
  });

  test('malformed polyline → malformedGeometry', () {
    final r = ride('10', 0, 0, 1);
    for (final bad in ['_p~iF~ps|U_', '_p~iF']) {
      final g = RouteGeometry({'10': [bad]});
      expect((matchRide(r, g) as RideLineUnavailable).gap,
          RideLineGap.malformedGeometry);
    }
  });

  group('synthetic', () {
    // A straight east–west line along latitude 1.3: (1.3, 103.80) →
    // (1.3, 103.81) → (1.3, 103.82), about 2.2 km (computed with
    // encodePolyline; decodes back to these points).
    const line = '_||F_mpxR?o}@?o}@';
    final g = RouteGeometry({'S': [line]});
    MapRide on(List<LatLng> stops) =>
        MapRide(service: 'S', sourceDirection: 0, boardIndex: 0, stops: stops);

    test('stops in line order: drawn, sliced between them', () {
      final r = on(const [LatLng(1.3, 103.805), LatLng(1.3, 103.815)]);
      final drawn = matchRide(r, g) as RideLineDrawn;
      expect(drawn.points.first.longitude, closeTo(103.805, 1e-6));
      expect(drawn.points.last.longitude, closeTo(103.815, 1e-6));
      expect(lengthOf(drawn.points), closeTo(1112, 5));
    });

    test('a stop out of order (backwards between two others) → notMatched', () {
      final r = on(const [
        LatLng(1.3, 103.805), LatLng(1.3, 103.818), LatLng(1.3, 103.810),
      ]);
      expect((matchRide(r, g) as RideLineUnavailable).gap,
          RideLineGap.notMatched);
    });

    test('a stop farther than 60 m from the line → notMatched', () {
      final r = on(const [LatLng(1.3, 103.805), LatLng(1.3008, 103.815)]);
      // 0.0008° latitude ≈ 89 m off the line
      expect((matchRide(r, g) as RideLineUnavailable).gap,
          RideLineGap.notMatched);
    });

    test('a hop more than 3× its straight line → notMatched', () {
      // A U-shaped open line: (1.3, 103.80) → (1.3, 103.82) → (1.3009, 103.82)
      // → (1.3009, 103.80). The two stops are its two ends, 100 m apart, but
      // about 4.5 km apart along it. The ends are 100 m apart (> 60 m), so the
      // line is not closed and is never doubled.
      const u = '_||F_mpxR?_|BsD??~{B';
      final r = MapRide(service: 'U', sourceDirection: 0, boardIndex: 0,
          stops: const [LatLng(1.3, 103.80), LatLng(1.3009, 103.80)]);
      expect((matchRide(r, RouteGeometry({'U': [u]})) as RideLineUnavailable).gap,
          RideLineGap.notMatched);
    });
  });
}
```

The synthetic encoded strings were computed with the Task 7 `encodePolyline` from the stated points, and
decode back to them.

- [ ] **Step 3: Run, expect failure.** `flutter test test/features/map/ride_geometry_test.dart`. Expected: it
  fails to compile.
- [ ] **Step 4: Implement `route_geometry.dart`** exactly as in "Domain interfaces".
- [ ] **Step 5: Implement `ride_geometry.dart`.**

```dart
import 'dart:math' as math;

import '../../../core/config/app_config.dart';
import '../../../core/geo/geo.dart';
import 'polyline_codec.dart';
import 'route_geometry.dart';

/// The bus ride the planner chose, as the map needs it (P2-M2).
class MapRide {
  const MapRide({
    required this.service,
    required this.sourceDirection,
    required this.boardIndex,
    required this.stops,
  });

  final String service;

  /// busrouter's direction index (BusService.sourceDirectionOf).
  final int sourceDirection;

  /// The planner's boarding occurrence (BusOption.boardIndex).
  final int boardIndex;

  /// Boarding … alighting stop positions, in ride order (at least 2).
  final List<LatLng> stops;

  @override
  bool operator ==(Object other) =>
      other is MapRide &&
      other.service == service &&
      other.sourceDirection == sourceDirection &&
      other.boardIndex == boardIndex &&
      _samePoints(other.stops, stops);

  @override
  int get hashCode => Object.hash(service, sourceDirection, boardIndex,
      Object.hashAll([for (final p in stops) Object.hash(p.latitude, p.longitude)]));
}

bool _samePoints(List<LatLng> a, List<LatLng> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].latitude != b[i].latitude || a[i].longitude != b[i].longitude) {
      return false;
    }
  }
  return true;
}

/// Why a ride has no line. Each is a degraded map, never a routing failure.
enum RideLineGap { noGeometry, malformedGeometry, notMatched }

sealed class RideLine {
  const RideLine(this.ride);

  /// The ride this result was worked out for. Draw it only for that ride.
  final MapRide ride;
}

final class RideLineDrawn extends RideLine {
  const RideLineDrawn(super.ride, this.points);

  /// The ride on the road, boarding end first (at least 2 points).
  final List<LatLng> points;
}

final class RideLineUnavailable extends RideLine {
  const RideLineUnavailable(super.ride, this.gap);
  final RideLineGap gap;
}

class RideMatchConfig {
  const RideMatchConfig({
    this.toleranceMeters = MapConfig.rideStopToleranceMeters,
    this.mergeWithinMeters = MapConfig.rideCandidateMergeMeters,
    this.maxDetour = MapConfig.rideMaxDetour,
    this.detourMinStraightMeters = MapConfig.rideDetourMinStraightMeters,
  });

  final double toleranceMeters;
  final double mergeWithinMeters;
  final double maxDetour;
  final double detourMinStraightMeters;
}

/// The ride's line on its route geometry, or why there is none. All or
/// nothing: every ride stop must match in order (docs/assumptions.md "Bus
/// ride line"); a straight stand-in is never drawn. Pure: no I/O.
RideLine matchRide(
  MapRide ride,
  RouteGeometry geometry, {
  RideMatchConfig config = const RideMatchConfig(),
}) {
  final encoded = geometry.encoded(ride.service, ride.sourceDirection);
  if (encoded == null) return RideLineUnavailable(ride, RideLineGap.noGeometry);
  final List<LatLng> line;
  try {
    line = decodePolyline(encoded);
  } on FormatException {
    return RideLineUnavailable(ride, RideLineGap.malformedGeometry);
  }
  if (line.length < 2 || ride.stops.length < 2) {
    return RideLineUnavailable(ride, RideLineGap.malformedGeometry);
  }
  // As given; stored backwards. A loop whose geometry starts at another stop
  // is doubled, but only when the line is closed: doubling an open line adds
  // a straight segment from its end back to its start, and a stop matched
  // there would be drawn as a straight stand-in (never drawn, D1).
  final reversed = line.reversed.toList();
  final closed = haversineMeters(line.first, line.last) <= config.toleranceMeters;
  for (final variant in [
    line,
    reversed,
    if (closed) ...[[...line, ...line], [...reversed, ...reversed]],
  ]) {
    final points = _matchAndSlice(ride.stops, variant, config);
    if (points != null) return RideLineDrawn(ride, points);
  }
  return RideLineUnavailable(ride, RideLineGap.notMatched);
}

/// A point in metres on a local plane around Singapore (equirectangular;
/// error far below the 60 m tolerance at this latitude).
class _P {
  const _P(this.x, this.y);
  factory _P.of(LatLng p) => _P(
    p.longitude * _metresPerDegree * _cosLat,
    p.latitude * _metresPerDegree,
  );
  static const double _metresPerDegree = 6371008.8 * math.pi / 180;
  static final double _cosLat = math.cos(1.35 * math.pi / 180);
  final double x, y;
  double distanceTo(_P o) => math.sqrt(math.pow(x - o.x, 2) + math.pow(y - o.y, 2));
}

/// One pass of the line near a stop: metres [along] the line, the segment
/// [k] and the fraction [t] along it, and the [offset] from the stop.
typedef _Hit = ({double along, int k, double t, double offset});

List<LatLng>? _matchAndSlice(List<LatLng> stops, List<LatLng> line,
    RideMatchConfig c) {
  final pts = [for (final p in line) _P.of(p)];
  final cumulative = <double>[0];
  for (var k = 0; k + 1 < pts.length; k++) {
    cumulative.add(cumulative.last + pts[k].distanceTo(pts[k + 1]));
  }
  final hits = <List<_Hit>>[];
  for (final s in stops) {
    final h = _hitsNear(_P.of(s), pts, cumulative, c);
    if (h.isEmpty) return null;
    hits.add(h);
  }

  // Least total along-line length over in-order chains, one hit per stop.
  var total = <double?>[for (final _ in hits[0]) 0];
  final from = <List<int>>[[for (final _ in hits[0]) -1]];
  for (var i = 1; i < hits.length; i++) {
    final straight = haversineMeters(stops[i - 1], stops[i]);
    final next = List<double?>.filled(hits[i].length, null);
    final prev = List<int>.filled(hits[i].length, -1);
    for (var b = 0; b < hits[i].length; b++) {
      for (var a = 0; a < hits[i - 1].length; a++) {
        final before = total[a];
        if (before == null) continue;
        final hop = hits[i][b].along - hits[i - 1][a].along;
        if (hop <= 0) continue; // must move forward along the line
        if (straight > c.detourMinStraightMeters &&
            hop > c.maxDetour * straight) {
          continue;
        }
        final sum = before + hop;
        if (next[b] == null || sum < next[b]!) {
          next[b] = sum;
          prev[b] = a;
        }
      }
    }
    if (next.every((v) => v == null)) return null;
    total = next;
    from.add(prev);
  }

  var end = -1;
  for (var b = 0; b < total.length; b++) {
    if (total[b] != null && (end < 0 || total[b]! < total[end]!)) end = b;
  }
  var start = end;
  for (var i = hits.length - 1; i > 0; i--) {
    start = from[i][start];
  }
  return _slice(line, hits.first[start], hits.last[end]);
}

List<_Hit> _hitsNear(_P p, List<_P> pts, List<double> cumulative,
    RideMatchConfig c) {
  final found = <_Hit>[];
  for (var k = 0; k + 1 < pts.length; k++) {
    final a = pts[k], b = pts[k + 1];
    final dx = b.x - a.x, dy = b.y - a.y, l2 = dx * dx + dy * dy;
    final t = l2 == 0
        ? 0.0
        : (((p.x - a.x) * dx + (p.y - a.y) * dy) / l2).clamp(0.0, 1.0);
    final offset = p.distanceTo(_P(a.x + t * dx, a.y + t * dy));
    if (offset <= c.toleranceMeters) {
      found.add((along: cumulative[k] + t * math.sqrt(l2), k: k, t: t,
          offset: offset));
    }
  }
  found.sort((u, v) => u.along.compareTo(v.along));
  final merged = <_Hit>[];
  for (final h in found) {
    if (merged.isNotEmpty && h.along - merged.last.along < c.mergeWithinMeters) {
      if (h.offset < merged.last.offset) merged.last = h;
    } else {
      merged.add(h);
    }
  }
  return merged;
}

LatLng _at(List<LatLng> line, int k, double t) {
  final a = line[k], b = line[k + 1];
  return LatLng(a.latitude + t * (b.latitude - a.latitude),
      a.longitude + t * (b.longitude - a.longitude));
}

List<LatLng> _slice(List<LatLng> line, _Hit from, _Hit to) => [
  _at(line, from.k, from.t),
  for (var k = from.k + 1; k <= to.k; k++) line[k],
  _at(line, to.k, to.t),
];
```

- [ ] **Step 6: Run.** `flutter test test/features/map/ride_geometry_test.dart`. Expected: all pass.
  - If a fixture length is outside ± 5 m: debug it, and do not widen the tolerance. The Python measurement
    used this exact algorithm; a gap means a porting bug.
  - If 2B/0 0 → 3 or 10/1 0 → 1 matches: re-check the closed-line rule, the variant loop and the detour cap.
- [ ] **Step 7: Mutation checks** (revert each one after it fails):
  1. Drop the doubled variants. The 115/0 test must fail.
  2. Double every line (remove `if (closed)`). The 10/1 open-line test must fail.
  3. Drop `reversed`. The 46/1 test must fail.
  4. Change `hop <= 0` to `hop < -1e9`. The out-of-order test must fail.
- [ ] **Step 8: Commit.**
  `git commit -m "feat(map): match and slice a planned bus ride on busrouter geometry"`

### Task 5: Load `routes.min.json` (data layer)

**Files:**

- Modify: `lib/core/config/app_config.dart` (`BusrouterEndpoints.routes`)
- Modify: `lib/core/errors/app_failure.dart` (`StaticDataset.busRouteGeometry`)
- Create: `lib/features/map/data/busrouter_routes_parser.dart`
- Create: `lib/features/map/data/busrouter_route_geometry_repository.dart`
- Test: `test/features/map/busrouter_routes_test.dart`
- Modify: `test/core/app_failure_test.dart`
- Modify: `test/web/content_security_policy_test.dart`

**Interfaces:**

- Produces:
  - `RouteGeometry parseBusrouterRoutes(Object? json)`, which throws `StaticDataUnavailable(busRouteGeometry)`;
  - `class BusrouterRouteGeometryRepository implements RouteGeometryRepository` with constructor
    `(JsonHttpClient http)`.

- [ ] **Step 1: Failing tests.**
  - **Parser:**
    - the captured fixture parses: 5 services, `encoded('10', 0)` non-null, `encoded('10', 2)` null;
    - a service whose value isn't a list of 1–2 strings is skipped;
    - more than `BusrouterValidation.maxInvalidShare` invalid entries → `StaticDataUnavailable` with
      `dataset == StaticDataset.busRouteGeometry`;
    - not an object, or an empty object → the same failure.
  - **Repository** (copy the structure of the `BusrouterRepository` tests, using a `MockClient`):
    - lazy: zero requests until `load()`;
    - one GET to `BusrouterEndpoints.routes`;
    - two concurrent `load()` calls send one request;
    - a success is reused;
    - a failure (500 after the client's retries, a 404, a 429, or a body over 4 MiB) throws
      `StaticDataUnavailable(busRouteGeometry)` and **is not cached**, so the next `load()` sends again.
  - **`app_failure_test`:** `StaticDataUnavailable(StaticDataset.busRouteGeometry).message ==
    'The bus route line is unavailable right now.'`
  - **CSP test:** add `BusrouterEndpoints.routes` to `providers`. The expected set is unchanged:
    `data.busrouter.sg` is already listed.
- [ ] **Step 2: Run and see them fail.**
- [ ] **Step 3: Implement.**
  - `app_config.dart` → in `BusrouterEndpoints`:

    ```dart
    /// One encoded polyline per service direction (P2-M2 ride line; loaded
    /// only when the map is opened with a direct-bus journey).
    static final Uri routes = Uri.parse(
      'https://data.busrouter.sg/v1/routes.min.json',
    );
    ```

  - `app_failure.dart`: add the value `busRouteGeometry` (doc: "busrouter route lines (the map)"), and the
    message case `StaticDataset.busRouteGeometry => 'The bus route line is unavailable right now.'`.
  - **Parser:** map entries to `List<String>` of length 1–2 after checking types, skip the rest, then apply the
    same invalid-share rule as `_checkShare` in `busrouter_parser.dart`, with the
    `StaticDataset.busRouteGeometry` dataset. Polylines are **not decoded here**; only the needed one is
    decoded, in the matcher.
  - **Repository:** the same shape as `BusrouterRepository`: a `Future<RouteGeometry>? _geometry`, an
    in-flight share, failures removed. It wraps `AppFailure` from `getJson` as
    `StaticDataUnavailable(StaticDataset.busRouteGeometry, '$e')`. In debug builds, `debugPrint` the service
    count.
- [ ] **Step 4: Run.** `flutter test test/features/map/busrouter_routes_test.dart test/core test/web`. Expected:
  pass.
- [ ] **Step 5: Commit.** `git commit -m "feat(map): load busrouter routes.min.json once per session"`

### Task 6: The scene and providers (lazy, one load, retry on Show map, never stale)

**Files:**

- Modify: `lib/features/map/domain/map_scene.dart`
- Modify: `lib/features/map/map_providers.dart`
- Test: `test/features/map/map_scene_test.dart`
- Test: `test/features/map/journey_map_card_test.dart` (provider behaviour through the real UI)

**Interfaces:**

- Consumes: Tasks 3–5.
- Produces:
  - `MapScene.ride`;
  - `buildMapScene(…, stops:)`;
  - `routeGeometryRepositoryProvider`, `routeGeometryProvider`, `rideLineProvider`.

- [ ] **Step 1: Failing scene tests** in `map_scene_test.dart`, using the fake network:
  - a direct bus gives `scene.ride` with `service 'F20'`, `boardIndex` equal to the option's, and stops equal
    to the positions of `fakeBusNetwork().services['F20'].directions[0]`, sliced `[boardIndex ..
    boardIndex + stops]`;
  - without `stops`, or for non-bus plans, `ride` is null;
  - `bounds` contains every ride stop;
  - two scenes that differ only in `ride` are not equal;
  - an option whose `directions[direction][boardIndex] != board.code` gives `ride == null`. This defensive
    case means a plan/network mismatch draws no line and changes nothing else.
- [ ] **Step 2: Implement the scene.** In `buildMapScene`, after `suggested`:

```dart
MapRide? ride;
if (suggested != null && stops != null) {
  final codes = suggested.service.directions[suggested.direction];
  final from = suggested.boardIndex, to = from + suggested.stops;
  if (to < codes.length &&
      codes[from] == suggested.board.code &&
      codes[to] == suggested.alight.code) {
    final positions = [
      for (final c in codes.sublist(from, to + 1)) ?stops[c]?.position,
    ];
    if (positions.length >= 2) {
      ride = MapRide(
        service: suggested.service.number,
        sourceDirection: suggested.service.sourceDirectionOf(suggested.direction),
        boardIndex: from,
        stops: positions,
      );
    }
  }
}
```

  Then:
  - pass `ride: ride` to `MapScene`;
  - extend `bounds` to iterate `[...markers.map((m) => m.position), ...?ride?.stops]`;
  - add `ride` to `==` and `hashCode`.

  If the Dart version rejects null-aware elements (`?expr`), use `.whereType<LatLng>()` instead.
- [ ] **Step 3: Failing provider/UI tests** in `journey_map_card_test.dart`. Add a counting fake: Task 7
  creates `FakeRouteGeometryRepository` with `loads`, `hold()`, `release()` and `failure`. If Task 7 isn't
  done, write it now; it belongs in Task 7's file anyway.

```dart
testWidgets('no routes.min.json request before "Show map", nor for a '
    'walk-only journey', (tester) async {
  await pumpApp(tester, app());
  await pickDestination(tester, 'VivoCity', 'VIVOCITY');
  await tester.pump(const Duration(seconds: 5));
  expect(geometry.loads, 0);
  await openMap(tester);
  expect(geometry.loads, 1);
});

testWidgets('one load per session: hide, reopen, change journey', (tester) async {
  await pumpApp(tester, app());
  await pickDestination(tester, 'VivoCity', 'VIVOCITY');
  await openMap(tester);
  await tester.tap(find.byKey(const Key('hide-map'))); await tester.pump();
  await openMap(tester);
  await tester.tap(find.byKey(const Key('change-destination'))); await tester.pump();
  await pickDestination(tester, 'ION Orchard', 'ION ORCHARD');
  expect(geometry.loads, 1);
});

testWidgets('a failed load is not retried until the user opens the map again',
    (tester) async {
  geometry.failure = const StaticDataUnavailable(StaticDataset.busRouteGeometry);
  await pumpApp(tester, app());
  await pickDestination(tester, 'VivoCity', 'VIVOCITY');
  await openMap(tester);
  await tester.pump(const Duration(minutes: 2));
  expect(geometry.loads, 1, reason: 'no automatic retry');
  expect(find.byKey(const Key('map-ride-unavailable')), findsOneWidget);
  expect(find.byKey(const Key('map-marker-boarding')), findsOneWidget);
  geometry.failure = null;
  await tester.tap(find.byKey(const Key('hide-map'))); await tester.pump();
  await openMap(tester);
  expect(geometry.loads, 2);
  expect(find.byKey(const Key('map-ride-line')), findsOneWidget);
});
```

  For the walk-only half of the first test, add a second test. Pick a destination within 300 m of the origin;
  the fake places include `bishanMrtCc`, which is close to the fake Bishan fix. Open the map and expect
  `geometry.loads == 0`.
- [ ] **Step 4: Implement the providers** in `map_providers.dart`:

```dart
final routeGeometryRepositoryProvider = Provider<RouteGeometryRepository>(
  (ref) => BusrouterRouteGeometryRepository(ref.watch(jsonHttpClientProvider)),
);

/// busrouter routes.min.json, loaded the first time an open map shows a
/// direct-bus journey and then held for the session. A failure is held too,
/// with no automatic retry; the next "Show map" tries again (MapExpanded.show).
final routeGeometryProvider = FutureProvider<RouteGeometry>(
  (ref) => guardAppFailure(
    ref.watch(routeGeometryRepositoryProvider).load,
    context: 'bus route geometry',
  ),
);

/// The current scene's ride line; null when the scene has no ride. Watched
/// only by the open map, so nothing is fetched before "Show map". Derived
/// from the current scene, so it can never belong to an earlier journey.
final rideLineProvider = Provider<AsyncValue<RideLine>?>((ref) {
  final ride = ref.watch(mapSceneProvider.select((s) => s?.ride));
  if (ride == null) return null;
  return ref
      .watch(routeGeometryProvider)
      .whenData((geometry) => matchRide(ride, geometry));
});
```

  In `mapSceneProvider`, pass the stops, and **only** for a direct bus, so a walk-only journey never touches
  the bus network:

```dart
final current = plan.isLoading || plan.hasError ? null : plan.value;
final stops = current is DirectBusOptions
    ? ref.watch(busNetworkProvider).value?.stops
    : null;
return buildMapScene(…, plan: current, stops: stops);
```

  `MapExpanded.show`:

```dart
void show() {
  // Reopening the map is the user's retry for a failed route-line load.
  if (ref.read(routeGeometryProvider).hasError) {
    ref.invalidate(routeGeometryProvider);
  }
  state = true;
}
```

- [ ] **Step 5: Run** `flutter test test/features/map`. The line-drawing assertions can only pass after
  Task 7, so mark them `skip: 'Task 7'` for now and remove the skip in Task 7. Everything else must pass.
- [ ] **Step 6: Commit.**
  `git commit -m "feat(map): ride on the map scene; lazy, session-held route geometry"`

### Task 7: Draw the ride line; fakes; integration

**Files:**

- Modify: `lib/features/map/presentation/journey_map.dart`
- Create: `integration_test/fakes/fake_route_geometry.dart`
- Modify: `integration_test/fakes/test_app.dart`
- Modify: `integration_test/happy_path_test.dart`
- Test: `test/features/map/journey_map_card_test.dart`

**Interfaces:**

- Consumes: `rideLineProvider`, `RideLineDrawn`, `MapScene.ride`.
- Produces:
  - widget keys `map-ride-line` (on the `PolylineLayer`) and `map-ride-unavailable` (the note);
  - `encodePolyline(List<LatLng>) → String`;
  - `FakeRouteGeometryRepository`;
  - `buildTestApp(routeGeometry:)`.

- [ ] **Step 1: The fake** (Web-safe: no `~`, because the fakes are compiled for the Web runs too):

```dart
import 'dart:async';

import 'package:sg_smart_commute/core/errors/app_failure.dart';
import 'package:sg_smart_commute/core/geo/geo.dart';
import 'package:sg_smart_commute/features/map/domain/route_geometry.dart';

import 'fake_bus_network.dart';

/// Precision-5 Google polyline encoder for test data. Arithmetic only, so it
/// gives the same result on the VM and under dart2js.
String encodePolyline(List<LatLng> points) {
  final out = StringBuffer();
  var lastLat = 0, lastLng = 0;
  void put(int delta) {
    var v = delta < 0 ? -2 * delta - 1 : 2 * delta;
    while (v >= 0x20) {
      out.writeCharCode((0x20 | (v & 0x1f)) + 63);
      v = v ~/ 32;
    }
    out.writeCharCode(v + 63);
  }
  for (final p in points) {
    final lat = (p.latitude * 1e5).round(), lng = (p.longitude * 1e5).round();
    put(lat - lastLat);
    put(lng - lastLng);
    lastLat = lat;
    lastLng = lng;
  }
  return out.toString();
}

/// Route lines for the fake network: each direction's line runs straight
/// through its stops, so every fake ride matches.
RouteGeometry fakeRouteGeometry() {
  final n = fakeBusNetwork();
  return RouteGeometry({
    for (final s in n.services.values)
      s.number: [
        for (final d in s.directions)
          encodePolyline([for (final c in d) n.stops[c]!.position]),
      ],
  });
}

class FakeRouteGeometryRepository implements RouteGeometryRepository {
  FakeRouteGeometryRepository({RouteGeometry? geometry})
    : geometry = geometry ?? fakeRouteGeometry();

  RouteGeometry geometry;
  AppFailure? failure;
  int loads = 0;
  Completer<void>? _gate;

  void hold() => _gate = Completer<void>();
  void release() => _gate?.complete();

  @override
  Future<RouteGeometry> load() async {
    loads++;
    final gate = _gate;
    if (gate != null) await gate.future;
    final f = failure;
    if (f != null) throw f;
    return geometry;
  }
}
```

  `buildTestApp`: add `RouteGeometryRepository? routeGeometry` and override
  `routeGeometryRepositoryProvider.overrideWithValue(routeGeometry ?? FakeRouteGeometryRepository())`. Update
  the `buildTestApp` doc comment.
- [ ] **Step 2: Failing widget tests.** Remove the Task 6 skips, then add:

```dart
testWidgets('the suggested ride is drawn on the road, under the markers',
    (tester) async {
  await pumpApp(tester, app());
  await pickDestination(tester, 'VivoCity', 'VIVOCITY');
  await openMap(tester);
  await tester.pump();
  final layer = tester.widget<PolylineLayer>(
    find.byKey(const Key('map-ride-line')));
  final points = layer.polylines.single.points;
  final stops = fakeBusNetwork().stops;   // F20: BSH2 → MID1 → VIV1
  expect(points.first.latitude, closeTo(stops['BSH2']!.position.latitude, 1e-4));
  expect(points.last.latitude, closeTo(stops['VIV1']!.position.latitude, 1e-4));
  // Drawn before the markers, so the pins stay on top.
  final children = tester.widget<FlutterMap>(find.byType(FlutterMap)).children;
  expect(children.indexWhere((w) => w is PolylineLayer),
      lessThan(children.indexWhere((w) => w is MarkerLayer)));
});

testWidgets('geometry that cannot be matched: markers, a note, no line, '
    'journey card unchanged', (tester) async {
  geometry.geometry = RouteGeometry({'F20': [encodePolyline(const [
    LatLng(1.40, 103.70), LatLng(1.41, 103.71)])]}); // nowhere near the ride
  await pumpApp(tester, app());
  await pickDestination(tester, 'VivoCity', 'VIVOCITY');
  await openMap(tester);
  await tester.pump();
  expect(find.byKey(const Key('map-ride-line')), findsNothing);
  expect(find.byKey(const Key('map-ride-unavailable')), findsOneWidget);
  for (final k in ['origin', 'boarding', 'alighting', 'destination']) {
    expect(find.byKey(Key('map-marker-$k')), findsOneWidget);
  }
  expect(find.text('Take Bus F20 toward VivoCity (fake)'), findsOneWidget);
});

testWidgets('changing journey while the line loads never shows the old line',
    (tester) async {
  geometry.hold();
  await pumpApp(tester, app());
  await pickDestination(tester, 'VivoCity', 'VIVOCITY');
  await openMap(tester);
  await tester.tap(find.byKey(const Key('change-destination')));
  await tester.pump();
  await pickDestination(tester, 'ION Orchard', 'ION ORCHARD'); // F30 BSH1→ION1
  geometry.release();
  await tester.pump(); await tester.pump();
  final points = tester.widget<PolylineLayer>(
    find.byKey(const Key('map-ride-line'))).polylines.single.points;
  final ion = fakeBusNetwork().stops['ION1']!.position;
  expect(points.last.latitude, closeTo(ion.latitude, 1e-4));
});
```

  Also add a **pure** guard test in `ride_geometry_test.dart` or a small presentation helper test:
  `JourneyMap` draws a `RideLineDrawn` only when `line.ride == scene.ride`. Pump `JourneyMap` directly with a
  scene for ride A, and override `rideLineProvider` to return `AsyncData(RideLineDrawn(rideB, …))`. Expect no
  `map-ride-line`.
- [ ] **Step 3: Implement in `journey_map.dart`.** Watch the line:

```dart
final rideLine = ref.watch(rideLineProvider);
final drawn = switch (rideLine?.value) {
  final RideLineDrawn line when line.ride == widget.scene.ride => line,
  _ => null,
};
final rideUnavailable = widget.scene.ride != null &&
    (rideLine?.hasError == true ||
     rideLine?.value is RideLineUnavailable);
```

  Insert before the `MarkerLayer`:

```dart
if (drawn != null)
  PolylineLayer(
    key: const Key('map-ride-line'),
    polylines: [
      Polyline(
        points: [for (final p in drawn.points) _toMap(p)],
        strokeWidth: 5,
        color: theme.colorScheme.primary,
        borderStrokeWidth: 2,
        borderColor: theme.colorScheme.surface,
      ),
    ],
  ),
```

  Below the map, beside the P2-M1 tiles note, use the same row style:

```dart
if (rideUnavailable)
  Semantics(liveRegion: true, child: Padding(
    key: const Key('map-ride-unavailable'),
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
    child: Row(children: [
      Icon(Icons.route_outlined, size: 18, color: theme.colorScheme.onSurfaceVariant),
      const SizedBox(width: 8),
      Expanded(child: Text(JourneyMap.rideLineUnavailable,
          style: theme.textTheme.bodySmall)),
    ]),
  )),
```

  with `static const String rideLineUnavailable = "The bus route line isn't available for this ride. The stops
  are shown.";`

  Update the map's screen-reader summary: when a line is drawn, `MapScene.summary` stays the same. The line is
  visual only, and the journey card has the stops. Leave `summary` unchanged.
- [ ] **Step 4: Integration.** In `happy_path_test.dart`, after the P2-M1 marker checks, add
  `await pumpUntilFound(tester, find.byKey(const Key('map-ride-line')));`. Also update the header comment
  ("…the ride line, from fake route geometry").
- [ ] **Step 5: Run.**
  - `flutter test test/features/map`. Expected: pass.
  - `flutter test`. Expected: all pass.
- [ ] **Step 6: Mutation checks.**
  - Remove the `line.ride == widget.scene.ride` guard: the guard test must fail.
  - Make `rideLineProvider` watch `routeGeometryProvider` before the null check: the walk-only test must fail
    (`loads == 1`).

  Restore both.
- [ ] **Step 7: Commit.** `git commit -m "feat(map): draw the planned bus ride on the journey map"`

### Task 8: Documentation

**Files:** `docs/map-feasibility.md`, `docs/assumptions.md`, `docs/architecture.md`, `docs/data-sources.md`,
`CLAUDE.md`, `docs/testing.md`

- [ ] **`map-feasibility.md`:**
  - §5: replace rule 2 with D1, "markers only, no straight stand-in", decided 2026-10-03;
  - §5: note that the production matcher is the simplified ride matcher (D2, with its numbers);
  - §11, decision 2: decided;
  - §10, P2-M2: "Done", plus the decisions (D3–D5).
- [ ] **`assumptions.md`:** add rows:
  - **"Bus ride line"**: all-or-nothing; 60 m / 40 m / 3× when over 50 m; variants; the slice; drawn under the
    pins; the note; a degraded visualisation, not a routing failure;
  - **"Route geometry load"**: lazy after "Show map" with a direct bus; session-held; a failure is held with
    no automatic retry, and the next "Show map" retries;
  - **"Map camera"**: bounds now include the ride's stops (D5).
- [ ] **`architecture.md`:** a "Phase 2 Milestone 2" section:
  - files and responsibilities;
  - data flow (`BusOption` → `MapRide` → `matchRide` → `RideLine`);
  - D3/D4 (the planner and parser additions, with no behaviour change);
  - flutter_map stays in presentation;
  - no CSP change.
- [ ] **`data-sources.md`:** in the busrouter section, add `routes.min.json`:
  - endpoint, size, `max-age`, shape;
  - used only by the map, lazily;
  - failure → markers only.
- [ ] **`CLAUDE.md`:**
  - in the Map flow, add the ride line (lazy `routeGeometryProvider`, pure `matchRide`, all-or-nothing, guard);
  - in the Testing seams list, add `routeGeometryRepositoryProvider`.
- [ ] **`testing.md`:**
  - in the dev-tools paragraph, add `tool/capture_route_geometry_fixtures.dart`;
  - add run-log rows (Task 9).
- [ ] **Commit:** `git commit -m "docs(p2-m2): record the ride-line design, rules and decisions"`

### Task 9: Final verification and PR

- [ ] **Gates** on the final head. Record each command and its real result in `docs/testing.md`.

```bash
dart format --set-exit-if-changed .
flutter analyze
flutter test
flutter test --platform chrome test/features/map/polyline_codec_test.dart
flutter build web
flutter build apk --debug
flutter test integration_test -d <android-device-id>
# Web, one file per run, chromedriver matching Chrome on port 4444:
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/app_boot_test.dart -d web-server --browser-name=chrome --profile
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/happy_path_test.dart -d web-server --browser-name=chrome --profile
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/fallback_path_test.dart -d web-server --browser-name=chrome --profile
```

- [ ] **Live Web check** (release build served locally, the real CSP; the same method as P2-M1 in
  `docs/testing.md`), Bishan → VivoCity:
  - before "Show map": 0 requests to `routes.min.json` and 0 tile requests (resource timing);
  - after it: exactly 1 `routes.min.json` (200) and the P2-M1 tile pattern;
  - Bus 57's line follows the road from Bishan Int to HarbourFront;
  - hide and reopen, and change destination: still 1 `routes.min.json` request;
  - block `*routes.min.json*` through CDP: markers plus the note, the journey card unchanged; then unblock,
    hide, show: the line appears (the retry on Show map);
  - dark mode: the line is readable on the Night tiles;
  - 0 CSP violations.
- [ ] **Live Android check** (release APK, emulator; if the GNSS ANR recurs, use a searched origin as in
  P2-M1 and record that): the same journey, line drawn, Night mode readable, hide/show. Restore any emulator
  setting you change.
- [ ] **Scope audit:**
  - `flutter_map` / `latlong2` imported only in `lib/features/map/presentation/`;
  - `features/journey` does not import `features/map`;
  - no new dependency, no CSP policy change, no secrets;
  - the planner's answers are unchanged (all planner tests untouched and passing).
- [ ] **Commit** the run log, push the feature branch, and open a PR against `main` ("feat(map): P2-M2 bus
  ride line from busrouter geometry"). Stop for review. Do not start P2-M3.

---

## Commit boundaries (summary)

1. `test(p2-m2): capture busrouter route geometry fixtures`
2. `feat(map): Web-safe precision-5 polyline decoder`
3. `feat(journey): expose the boarding occurrence and busrouter direction index`
4. `feat(map): match and slice a planned bus ride on busrouter geometry`
5. `feat(map): load busrouter routes.min.json once per session`
6. `feat(map): ride on the map scene; lazy, session-held route geometry`
7. `feat(map): draw the planned bus ride on the journey map`
8. `docs(p2-m2): record the ride-line design, rules and decisions`
9. `docs(testing): P2-M2 gates and live checks`

Each commit builds and passes `flutter test`; Task 6's line-drawing assertions are skipped until Task 7.

## Required-test coverage map

| Required test | Where |
|---|---|
| Known Bus 10 03019 → 14141 | Task 4 `Bus 10, 03019 → 14141` |
| Positive and negative deltas | Task 2 reference polyline |
| Web-safe decoder behaviour | Task 2 large negative delta, run with `--platform chrome` + the mutation check |
| Normal direction | Task 4 `4/0 0 → 1` and Bus 10 |
| Reversed geometry | Task 4 `46/1` |
| Loop service | Task 4 `4/0` (loop, given), `115/0` (closed loop, doubled), `10/1` (open line never doubled) |
| Repeated stop | Task 4 `11/0` 6 → 8 vs 17 → 19; Task 3 planner `boardIndex` |
| Boarding/alighting ordering | Task 4 out-of-order; Task 3 invariant |
| Malformed polyline | Task 2 malformed inputs; Task 4 `malformedGeometry` |
| Missing service/direction geometry | Task 4 `noGeometry`; Task 3 `sourceDirectionOf` |
| Stop too far from geometry | Task 4 synthetic 89 m |
| Map usable with markers when geometry fails | Task 6 failed load; Task 7 unmatched geometry |
| No geometry request before Show map | Task 6 first test (+ walk-only) |
| Only one routes.min.json load per session | Task 6 second test; Task 5 repository |
| Changing journeys cannot show stale geometry | Task 7 hold/release test + the guard test |

## Self-review notes

- **Spec coverage:** every bullet in the request maps to a task above (lazy load: T5/T6; session cache:
  T5/T6; size, rate-limit and error handling through `JsonHttpClient`: T5; decoder and Web-safe: T2;
  direction: T3/T4; matching: T4; loops, repeats, reversed and doubled: T4; slicing: T4; a mismatch cannot
  change the plan: T6 defensive case + T7 card check; graceful failure: the table, T6, T7; flutter_map
  confined: D6 + T9 audit; reasonable use preserved: Global Constraints + T9).
- **Types used consistently:** `MapRide`, `RideLine`, `RideLineDrawn`, `RideLineUnavailable`, `RideLineGap`,
  `RouteGeometry.encoded`, `BusOption.boardIndex`, `BusService.sourceDirectionOf`, `rideLineProvider`,
  `routeGeometryProvider`, `routeGeometryRepositoryProvider`.
- **Literals:** every encoded string in Tasks 2 and 4 was computed with the Task 7 encoder (which reproduces
  Google's reference string `` _p~iF~ps|U_ulLnnqC_mqNvxq`@ `` exactly) and decodes back to the stated points. The
  fixture lengths come from the scratch run of exactly this algorithm on live data, 2026-10-03.
- **Found while self-reviewing:** doubling an open line matches through an artificial straight segment.
  That's a hidden straight stand-in, and the measured 142 rides would have shown it. Fixed by the closed-line
  rule (D2), with a regression test (10/1) and a mutation check.
