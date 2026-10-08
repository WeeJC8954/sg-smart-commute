# Simplification (over-engineering cuts) Implementation Plan

> **Status (2026-10-05):** plan only; intentionally not implemented as part of the completed project scope. Its
> checkboxes are not outstanding work.

> **For agentic workers:** if available, use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task by task. Steps use checkbox (`- [ ]`) syntax for
> tracking.

**Goal:** Remove layers and code that do nothing in this app, with **no change in behaviour**: same UI text, same
requests, same caching, same error handling.

**Architecture:** This is a pure refactor of the Flutter app in `lib/`. It makes session caching live only in
Riverpod providers, not also in the repositories. It uses Riverpod's own `AsyncValue` for per-stop arrival results
instead of a hand-made sealed type. It deletes settings providers nothing overrides, dead parameters and
template comments. Every task ends with the full test suite passing.

**Tech Stack:** Flutter 3.47.2 / Dart 3.13.2, `flutter_riverpod` 3.4.3, `package:http`, `flutter_test`.

**Spec:** this document. It comes from an over-engineering review (ponytail review) of `origin/main` at `2772b0a`
(2026-10-03). Project spec: `docs/singapore-smart-commute-implementation-guide.v2.md` (cited as `§N`).

## Before you start

- Read `CLAUDE.md` at the repo root first. It has the hard constraints, the commands and the test seams, and it
  overrides anything here that disagrees with it.
- Line numbers below are from `2772b0a`. If `main` has moved, find each edit by its quoted code, not its line.
- Branch first, off the latest `origin/main`. Never commit on `main`:
  ```bash
  git fetch origin
  git switch -c refactor/simplify origin/main
  ```
- The full suite is quick (about 480 tests, about 35 s). Run `flutter test` at the end of every task.

## Global Constraints

- No behaviour change. Every user-visible string, request count, cache rule and Retry action stays the same.
  A test may change only where its own task says so.
- Riverpod auto-retry stays off (`ProviderScope(retry: noAutomaticRetry)`). Tests build containers with
  `ProviderContainer(retry: noAutomaticRetry, ...)`.
- Errors stay typed `AppFailure`s (`lib/core/errors/app_failure.dart`). Widgets show `failureMessage(error)`.
- Gates must really pass. Never suppress a lint to go green. The gates are `dart format --set-exit-if-changed .`,
  `flutter analyze` and `flutter test`.
- Evidence rule: never claim a gate passed unless it ran. Record each final gate and its real result as a row in
  the run log at the end of `docs/testing.md`. Anything not run is logged as **Not run**, with the reason.
- Never commit or push to `main`. Push the branch and open a PR against `main`. Don't merge it: a person
  reviews it.

## Review Focus

These are behaviours a refactor here could quietly break. Each one is pinned by a test, and the task that owns
the test is named.

1. **MRT Retry after a failed asset load reloads the asset.** Once stations are cached in a provider, Retry must
   invalidate that provider as well. Otherwise the error stays forever. New widget test in Task 3.
2. **Bus data is downloaded once per session, however often origin or destination change.** Covered by the
   existing `journey_widget_test.dart` checks (`bus.loads` stays `1`) and the new provider test in Task 2.
3. **Bus data Retry after a failure downloads again.** Covered by the existing `journey_widget_test.dart` check
   (`bus.loads` becomes `2`, around line 313) and the repository test "HTTP failure → StaticDataUnavailable; a
   later load retries", which must keep passing in Task 2.
4. **One failed stop never hides another stop's arrivals.** The existing `journey_arrivals_test.dart` test "a
   failed stop is kept per stop …" is rewritten for `AsyncValue` in Task 4.
5. **A refresh while arrivals are still loading sends no duplicate requests.** The existing test "concurrent
   refreshes share in-flight requests" must keep passing unchanged in Task 4.

## Findings and decisions

Each finding in the review is either implemented here (Tasks 1–6) or deliberately left alone. **Don't implement
the "Left alone" items**: each has a reason that still holds.

| Finding | Decision |
|---|---|
| `pubspec.yaml` `flutter create` template comments | Task 1 |
| `BusrouterRepository` caches the network, and `busNetworkProvider` already does | Task 2 |
| `MrtAssetRepository` hand-rolls a session cache | Task 3: move it to a `FutureProvider` |
| `StopArrivalsResult` / `Loaded` / `Failed` is a hand-made `AsyncValue` (CLAUDE.md: "Don't add a parallel `LoadState` type") | Task 4 |
| `_Checking` widget wraps one const `BusyRow` | Task 4 |
| `plannerConfigProvider`, `uiTickIntervalProvider`, `environmentRefreshIntervalProvider`: nothing overrides them | Task 5 |
| `AppLogo.size`: no caller sets it | **Void since E4** (#62): `lib/app/about_dialog.dart` passes `const AppLogo(size: 48)`, so the parameter stays. Task 6 Step 1 is skipped |
| `_typeOf(block:)` in `onemap_parser.dart`: never read | Task 6 |
| `_Received` class in `json_http_client.dart` | Task 6: use a record |
| `SpatialScope.station`, unproduced `PlaceType` values, `PlaceSource` extra values, `SearchMode` on `search()`, `reverseGeocode` | **Left alone:** they are the guide's model (§6.2, §8.1) |
| `EnvironmentalReading.fetchedAt`/`source`, `Place.source`, `BusArrival.busStopCode`/`source` | **Left alone:** kept by the earlier issue #32 decision (guide model) |
| `BusStop.road`, `BusService.name` (not read by the UI) | **Left alone:** the guide's §9.1 data shape |
| `BusArrivalCache` in-flight dedup (`JsonHttpClient` also dedups) | **Left alone:** `BusArrivalRepository` doesn't promise dedup, and "concurrent refreshes share in-flight requests" pins it with a fake that has no HTTP layer |
| OneMap search cache capped at 50 queries (LRU) | **Left alone:** a deliberate bound from issue #16, in `docs/assumptions.md` |
| `OneMapPlaceSearchRepository` repeats the minimum-length check | **Left alone:** it is the repository's tested contract (no request for a too-short query) |
| Shared helper for the four environment `FutureProvider`s, the two bounds checks, or the two cards' focus code | **Left alone:** after `dart format` each saves at most 3 lines |
| `ReadingText.uv` daytime branch (the app only calls it at night) | **Left alone:** it saves 2 lines but changes a tested public function |

---

### Task 1: Drop the template comments from `pubspec.yaml`

**Files:**
- Modify: `pubspec.yaml` (whole file)

**Interfaces:** none.

- [ ] **Step 1: Replace `pubspec.yaml` with exactly this.** Only the comments go. Every key and value stays,
  and so does the comment that says where the MRT asset comes from.

```yaml
name: sg_smart_commute
description: "Singapore Smart Commute"
publish_to: 'none'

version: 1.0.0+1

environment:
  sdk: ^3.13.2

dependencies:
  flutter:
    sdk: flutter

  http: ^1.6.0
  flutter_riverpod: ^3.4.3
  geolocator: ^14.1.1
  clock: ^1.1.3

dev_dependencies:
  flutter_test:
    sdk: flutter

  flutter_lints: ^6.0.0
  integration_test:
    sdk: flutter
  fake_async: ^1.3.3

flutter:
  uses-material-design: true

  # Generated by tool/build_mrt_asset.dart (LTA MRT Station Exit, SODL).
  assets:
    - assets/mrt_stations.json
    - assets/app_icon.png
```

Before overwriting, diff the old file against this. If `main` has added a key that isn't here, keep that key.

- [ ] **Step 2: Check that nothing resolved differently.**

Run: `flutter pub get` then `git diff --exit-code pubspec.lock`
Expected: no diff, exit code 0.

- [ ] **Step 3: Commit.**

```bash
git add pubspec.yaml
git commit -m "chore: drop flutter create template comments from pubspec.yaml"
```

---

### Task 2: Cache the bus network only in `busNetworkProvider`

`busNetworkProvider` (`lib/features/journey/journey_providers.dart`) is a plain, non-autoDispose
`FutureProvider`. It already holds the network for the session, and Retry invalidates it after a failure.
`BusrouterRepository` keeps a second copy of the same future, and `JsonHttpClient` also merges identical
in-flight requests. The repository copy goes.

**Files:**
- Modify: `lib/features/journey/data/busrouter_repository.dart:10-59`
- Modify: `lib/features/journey/domain/bus_network_repository.dart:5-7` (doc comment)
- Test: `test/features/journey/busrouter_test.dart` (group `BusrouterRepository`, around lines 336-420)

**Interfaces:**
- Consumes: `busNetworkProvider`, `busNetworkRepositoryProvider` (`lib/features/journey/journey_providers.dart`),
  `noAutomaticRetry` (`package:sg_smart_commute/main.dart`).
- Produces: `BusrouterRepository.load()`, same signature. Each call now downloads again, and the provider is the
  only session cache.

- [ ] **Step 1: Add a provider-level test (it passes before the change and must pass after it).** In
  `test/features/journey/busrouter_test.dart`, add these imports beside the existing ones:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sg_smart_commute/features/journey/journey_providers.dart';
import 'package:sg_smart_commute/main.dart' show noAutomaticRetry;
```

Then, inside `group('BusrouterRepository', ...)`, replace these two tests:

```dart
    test('session cache: later loads reuse the first result', () async {
      final r = repo(ok);
      final a = await r.load();
      final b = await r.load();
      expect(identical(a, b), isTrue);
      expect((stopsCalls, servicesCalls), (1, 1));
    });

    test('concurrent loads share one download', () async {
      final r = repo(ok);
      final results = await Future.wait([r.load(), r.load(), r.load()]);
      expect(identical(results[0], results[2]), isTrue);
      expect((stopsCalls, servicesCalls), (1, 1));
    });
```

with:

```dart
    test('busNetworkProvider holds one download for the session, shared by '
        'concurrent and later reads', () async {
      final c = ProviderContainer(
        retry: noAutomaticRetry,
        overrides: [busNetworkRepositoryProvider.overrideWithValue(repo(ok))],
      );
      addTearDown(c.dispose);
      final first = await Future.wait([
        c.read(busNetworkProvider.future),
        c.read(busNetworkProvider.future),
      ]);
      final later = await c.read(busNetworkProvider.future);
      expect(identical(first[0], first[1]), isTrue);
      expect(identical(first[0], later), isTrue);
      expect((stopsCalls, servicesCalls), (1, 1));
    });
```

- [ ] **Step 2: Run it.**

Run: `flutter test test/features/journey/busrouter_test.dart`
Expected: PASS. The behaviour is pinned before the code changes.

- [ ] **Step 3: Remove the repository's cache.** Replace everything from the `/// busrouter.sg static data`
  doc comment to the end of `lib/features/journey/data/busrouter_repository.dart` with:

```dart
/// busrouter.sg static data behind [BusNetworkRepository] (guide v2.1 §9.1).
///
/// - Lazy: nothing is fetched until the first [load] (the first journey).
/// - Each [load] downloads and parses both files. `busNetworkProvider` holds
///   the result for the session, and [JsonHttpClient] merges concurrent
///   identical requests.
/// - Any network, HTTP or schema problem is [StaticDataUnavailable].
class BusrouterRepository implements BusNetworkRepository {
  BusrouterRepository(this._http);

  final JsonHttpClient _http;

  @override
  Future<BusNetwork> load() async {
    final List<Object?> both;
    try {
      both = await Future.wait([
        _http.getJson(BusrouterEndpoints.stops),
        _http.getJson(BusrouterEndpoints.services),
      ]);
    } on AppFailure catch (e) {
      throw StaticDataUnavailable(StaticDataset.busRoutes, '$e');
    }
    final [stopsJson, servicesJson] = both;
    final stops = parseBusrouterStops(stopsJson);
    final services = parseBusrouterServices(servicesJson, stops);
    if (kDebugMode) {
      debugPrint(
        'BusrouterRepository: ${stops.length} stops, '
        '${services.length} services',
      );
    }
    return BusNetwork(stops: stops, services: services);
  }
}
```

- [ ] **Step 4: Fix the interface doc.** In `lib/features/journey/domain/bus_network_repository.dart`, replace:

```dart
  /// The whole network, loaded once per session. Throws
  /// `StaticDataUnavailable` if it cannot be loaded or validated.
```

with:

```dart
  /// The whole network. `busNetworkProvider` holds it for the session.
  /// Throws `StaticDataUnavailable` if it cannot be loaded or validated.
```

- [ ] **Step 5: Run the suite.**

Run: `flutter test`
Expected: PASS, including `busrouter_test.dart` ("HTTP failure → StaticDataUnavailable; a later load retries"
still passes because the repository never cached failures) and `journey_widget_test.dart` (`bus.loads`
expectations).

- [ ] **Step 6: Format, analyze, commit.**

```bash
dart format --set-exit-if-changed .
flutter analyze
git add lib/features/journey/data/busrouter_repository.dart lib/features/journey/domain/bus_network_repository.dart test/features/journey/busrouter_test.dart
git commit -m "refactor(journey): hold the bus network only in busNetworkProvider"
```

---

### Task 3: Cache the MRT stations in a `FutureProvider`, not in the repository

`MrtAssetRepository` hand-rolls the same "cache the future, forget it on error" logic that Riverpod provides.
Move the cache into a new `mrtStationsProvider`, as Task 2 does for the bus network. **Retry on the journey card
must then invalidate `mrtStationsProvider`** (Review Focus 1).

**Files:**
- Modify: `lib/features/journey/data/mrt_asset_repository.dart:10-51`
- Modify: `lib/features/journey/journey_providers.dart:36-39` (add a provider after `mrtRepositoryProvider`) and
  `:78-98` (`mrtSuggestionProvider`)
- Modify: `lib/features/journey/presentation/journey_card.dart:65-69` (MRT Retry)
- Modify: `docs/architecture.md:118-119`
- Test: `test/features/journey/journey_widget_test.dart` (new test)
- Test: `test/features/journey/mrt_test.dart:175-190` (rewrite one test)

**Interfaces:**
- Consumes: `mrtRepositoryProvider` (unchanged type `Provider<MrtAssetRepository>`; `buildTestApp` overrides it).
- Produces: `final mrtStationsProvider = FutureProvider<List<MrtStation>>` in `journey_providers.dart`.
  `MrtAssetRepository.stations()` keeps its signature, but each call now reads the asset again.

- [ ] **Step 1: Add a widget test that pins MRT Retry (it passes before the change and must pass after it).** In
  `test/features/journey/journey_widget_test.dart`, add these imports:

```dart
import 'dart:convert';

import 'package:sg_smart_commute/features/journey/data/mrt_asset.dart';
import 'package:sg_smart_commute/features/journey/data/mrt_asset_repository.dart';
```

Add this test after `testWidgets('the MRT Retry says what it retries', ...)`:

```dart
  testWidgets('MRT Retry after a failed asset load loads it again', (
    tester,
  ) async {
    var fail = true;
    await pumpApp(
      tester,
      buildTestApp(
        location: FakeLocationService(
          access: LocationAccess.granted,
          position: bishan,
        ),
        environment: FakeEnvironmentRepository(),
        places: places,
        busNetwork: bus,
        mrt: MrtAssetRepository(
          load: () async {
            if (fail) throw Exception('asset missing');
            return jsonEncode({'stations': encodeMrtStations(fakeMrtStations)});
          },
        ),
        busArrivals: arrivals,
      ),
    );
    await searchAndPick(tester, destinationField, 'VivoCity', 'VIVOCITY');
    expect(
      inKey('journey-mrt', 'MRT station data is unavailable.'),
      findsOneWidget,
    );

    fail = false;
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('journey-mrt')),
        matching: find.text('Retry'),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    expect(
      inKey('journey-mrt', 'MRT station data is unavailable.'),
      findsNothing,
    );
    expect(
      textOf(tester, 'journey-mrt-origin'),
      startsWith('Nearest MRT: BISHAN MRT STATION'),
    );
  });
```

- [ ] **Step 2: Run it.**

Run: `flutter test test/features/journey/journey_widget_test.dart --plain-name "MRT Retry after a failed asset load"`
Expected: PASS on the current code.

- [ ] **Step 3: Strip the cache from the repository.** Replace everything from the `/// The bundled MRT station
  asset` doc comment to the end of `lib/features/journey/data/mrt_asset_repository.dart` with:

```dart
/// The bundled MRT station asset (guide v2.1 §9.5). A missing or malformed
/// asset is [StaticDataUnavailable]. `mrtStationsProvider` holds the result
/// for the session.
class MrtAssetRepository {
  MrtAssetRepository({Future<String> Function()? load})
    : _load = load ?? (() => rootBundle.loadString(mrtStationsAsset));

  final Future<String> Function() _load;

  Future<List<MrtStation>> stations() async {
    final String text;
    try {
      text = await _load();
    } catch (e) {
      throw StaticDataUnavailable(
        StaticDataset.mrtStations,
        'asset not loaded: $e',
      );
    }
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      throw const StaticDataUnavailable(StaticDataset.mrtStations, 'not JSON');
    }
    return parseMrtAsset(json);
  }
}
```

- [ ] **Step 4: Add `mrtStationsProvider` and use it.** In `lib/features/journey/journey_providers.dart`,
  add this right after the `mrtRepositoryProvider` declaration:

```dart

/// The MRT stations, read from the asset on first use and then held for the
/// session, as [busNetworkProvider] holds the bus network. A failure is held
/// until Retry on the journey card invalidates this provider.
final mrtStationsProvider = FutureProvider<List<MrtStation>>(
  (ref) => guardAppFailure(
    ref.watch(mrtRepositoryProvider).stations,
    context: 'MRT stations',
  ),
);
```

In `mrtSuggestionProvider`, replace:

```dart
      final stations = await guardAppFailure(
        ref.watch(mrtRepositoryProvider).stations,
        context: 'MRT stations',
      );
```

with:

```dart
      final stations = await ref.watch(mrtStationsProvider.future);
```

- [ ] **Step 5: Make MRT Retry reload the stations.** In `lib/features/journey/presentation/journey_card.dart`,
  replace:

```dart
              onRetry: () => ref.invalidate(mrtSuggestionProvider),
```

with:

```dart
              onRetry: () => ref
                ..invalidate(mrtStationsProvider)
                ..invalidate(mrtSuggestionProvider),
```

- [ ] **Step 6: Move the "once per session" test to the provider.** In `test/features/journey/mrt_test.dart`,
  add these imports:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sg_smart_commute/features/journey/journey_providers.dart';
import 'package:sg_smart_commute/main.dart' show noAutomaticRetry;
```

Replace the test `'repository loads once per session; a failure is retried'` (the whole `test(...)` call) with:

```dart
    test('mrtStationsProvider loads once per session; a failure is held '
        'until Retry invalidates it', () async {
      var loads = 0;
      var fail = true;
      final c = ProviderContainer(
        retry: noAutomaticRetry,
        overrides: [
          mrtRepositoryProvider.overrideWithValue(
            MrtAssetRepository(
              load: () async {
                loads++;
                if (fail) throw Exception('not yet');
                return jsonEncode(bundled);
              },
            ),
          ),
        ],
      );
      addTearDown(c.dispose);
      await expectLater(
        c.read(mrtStationsProvider.future),
        throwsA(isA<StaticDataUnavailable>()),
      );
      fail = false;
      expect(c.read(mrtStationsProvider).hasError, isTrue);
      c.invalidate(mrtStationsProvider); // Retry
      final a = await c.read(mrtStationsProvider.future);
      final b = await c.read(mrtStationsProvider.future);
      expect(identical(a, b), isTrue);
      expect(loads, 2);
    });
```

- [ ] **Step 7: Update the architecture doc.** In `docs/architecture.md` (Milestone 3 section), replace:

```markdown
- `journey_providers.dart`: `busNetworkProvider` (holds the network for the session), `journeyPlanProvider`
```

with:

```markdown
- `journey_providers.dart`: `busNetworkProvider` and `mrtStationsProvider` (hold the bus network and the MRT
  stations for the session; Retry invalidates them), `journeyPlanProvider`
```

- [ ] **Step 8: Run the suite.**

Run: `flutter test`
Expected: PASS, including the new MRT Retry widget test from Step 1.

- [ ] **Step 9: Format, analyze, commit.**

```bash
dart format --set-exit-if-changed .
flutter analyze
git add lib/features/journey docs/architecture.md test/features/journey
git commit -m "refactor(journey): hold MRT stations in mrtStationsProvider; Retry invalidates it"
```

---

### Task 4: Per-stop arrival results as `AsyncValue`

`StopArrivalsResult` (`StopArrivalsLoaded` / `StopArrivalsFailed`) duplicates Riverpod's
`AsyncData` / `AsyncError`, and CLAUDE.md says not to add a parallel `LoadState` type. Riverpod 3.4.3 has
`static Future<AsyncValue<T>> AsyncValue.guard<T>(Future<T> Function() future, ...)`, and `AsyncValue` is a
sealed class (`AsyncData`, `AsyncError`, `AsyncLoading`). `BusArrivalCache` already turns every error into a typed
`AppFailure`, so the `AsyncError.error` is still an `AppFailure`.

**Files:**
- Modify: `lib/features/bus_arrival/bus_arrival_providers.dart:1-109`
- Modify: `lib/features/bus_arrival/presentation/option_arrivals.dart:38-57,191-197`
- Modify: `docs/architecture.md:139`
- Test: `test/features/bus_arrival/journey_arrivals_test.dart` (three places)

**Interfaces:**
- Consumes: `BusArrivalCache.arrivalsAt(String) → Future<StopArrivals>` (unchanged).
- Produces: `JourneyArrivals.byStop` is now `Map<String, AsyncValue<StopArrivals>>`. Each value is
  `AsyncData<StopArrivals>` or `AsyncError<StopArrivals>`. `StopArrivalsResult`, `StopArrivalsLoaded`,
  `StopArrivalsFailed` and `_load` no longer exist.

- [ ] **Step 1: Update the tests to the new type (they will fail to compile until Step 3).** In
  `test/features/bus_arrival/journey_arrivals_test.dart`:

Replace:

```dart
      final bsh1 = result.byStop['BSH1']! as StopArrivalsLoaded;
      expect(nextArrivals(bsh1.arrivals, 'F10', now: now), hasLength(2));
      expect(nextArrivals(bsh1.arrivals, 'F30', now: now), hasLength(1));
```

with:

```dart
      final bsh1 = result.byStop['BSH1']!.requireValue;
      expect(nextArrivals(bsh1, 'F10', now: now), hasLength(2));
      expect(nextArrivals(bsh1, 'F30', now: now), hasLength(1));
```

Replace:

```dart
      expect(result.byStop['BSH2'], isA<StopArrivalsFailed>());
      expect(
        (result.byStop['BSH2']! as StopArrivalsFailed).failure,
        isA<NetworkUnavailable>(),
      );
      expect(result.byStop['BSH1'], isA<StopArrivalsLoaded>());
```

with:

```dart
      expect(result.byStop['BSH2'], isA<AsyncError<StopArrivals>>());
      expect(result.byStop['BSH2']!.error, isA<NetworkUnavailable>());
      expect(result.byStop['BSH1'], isA<AsyncData<StopArrivals>>());
```

Replace (in "Retry recovers after a failure …"):

```dart
    expect(result.byStop['BSH2'], isA<StopArrivalsLoaded>());
```

with:

```dart
    expect(result.byStop['BSH2'], isA<AsyncData<StopArrivals>>());
```

Then check that no test still names the old types:

Run: `git grep -n "StopArrivalsLoaded\|StopArrivalsFailed\|StopArrivalsResult" -- test integration_test`
Expected: no output.

- [ ] **Step 2: Run the file to see it fail.**

Run: `flutter test test/features/bus_arrival/journey_arrivals_test.dart`
Expected: FAIL (compile errors: `requireValue` / `error` don't exist on `StopArrivalsResult`).

- [ ] **Step 3: Change the provider.** In `lib/features/bus_arrival/bus_arrival_providers.dart`:

Delete the import `import '../../core/errors/app_failure.dart';` (it becomes unused).

Delete the whole block from `/// One stop's outcome. A failed stop never hides another stop's arrivals,` through
the end of `final class StopArrivalsFailed ... }` (the sealed class and both subclasses).

In `class JourneyArrivals`, replace:

```dart
  final Map<String, StopArrivalsResult> byStop;
```

with:

```dart
  /// Per boarding stop: `AsyncData` with its arrivals, or `AsyncError` with
  /// its typed `AppFailure`. A failed stop never hides another stop's
  /// arrivals, and never removes the static route.
  final Map<String, AsyncValue<StopArrivals>> byStop;
```

In `journeyArrivalsProvider`, replace:

```dart
    for (final stop in stops) _load(cache, stop),
```

with:

```dart
    for (final stop in stops) AsyncValue.guard(() => cache.arrivalsAt(stop)),
```

Delete the whole `Future<StopArrivalsResult> _load(BusArrivalCache cache, String stop) async { ... }` function.
If `BusArrivalCache` is now named only in `busArrivalCacheProvider`, its import stays (that provider uses it).

- [ ] **Step 4: Change the widget and inline `_Checking`.** In
  `lib/features/bus_arrival/presentation/option_arrivals.dart`, replace:

```dart
    if (current == null) {
      if (async case AsyncValue(:final error?, isLoading: false)) {
        return _ArrivalFailed(error: error, service: option.service.number);
      }
      return const _Checking();
    }
    return switch (current.byStop[option.board.code]) {
      null => const _Checking(),
      StopArrivalsFailed(:final failure) => _ArrivalFailed(
        error: failure,
        service: option.service.number,
      ),
      StopArrivalsLoaded(:final arrivals) => _loaded(
        theme,
        arrivals,
        now,
        current.checkedAt,
      ),
    };
```

with:

```dart
    if (current == null) {
      if (async case AsyncValue(:final error?, isLoading: false)) {
        return _ArrivalFailed(error: error, service: option.service.number);
      }
      return const BusyRow(checking, compact: true);
    }
    return switch (current.byStop[option.board.code]) {
      AsyncData(:final value) => _loaded(
        theme,
        value,
        now,
        current.checkedAt,
      ),
      AsyncError(:final error) => _ArrivalFailed(
        error: error,
        service: option.service.number,
      ),
      _ => const BusyRow(checking, compact: true),
    };
```

Delete the class:

```dart
class _Checking extends StatelessWidget {
  const _Checking();

  @override
  Widget build(BuildContext context) =>
      const BusyRow(OptionArrivals.checking, compact: true);
}
```

- [ ] **Step 5: Update the architecture doc.** In `docs/architecture.md` (Milestone 4 section), replace:

```markdown
  fetched for, the check time and a per-stop result (`StopArrivalsLoaded` / `StopArrivalsFailed`). Widgets show it
```

with:

```markdown
  fetched for, the check time and a per-stop result (`AsyncData` / `AsyncError`). Widgets show it
```

- [ ] **Step 6: Run the suite.**

Run: `flutter test`
Expected: PASS. `journey_arrivals_test.dart` passes, including "concurrent refreshes share in-flight requests"
(unchanged), and so does `arrivals_widget_test.dart`.

- [ ] **Step 7: Format, analyze, commit.**

```bash
dart format --set-exit-if-changed .
flutter analyze
git add lib/features/bus_arrival docs/architecture.md test/features/bus_arrival/journey_arrivals_test.dart
git commit -m "refactor(bus_arrival): per-stop results as AsyncValue, not a parallel sealed type"
```

---

### Task 5: Delete providers nothing overrides

No test, fake or app code overrides `plannerConfigProvider`, `uiTickIntervalProvider` or
`environmentRefreshIntervalProvider` (checked with `git grep` on `2772b0a`). Use their constants directly.
Tests that need other planner tunables already pass a `PlannerConfig` straight to `planDirectBus`.

**Files:**
- Modify: `lib/features/journey/journey_providers.dart:48-51,67-73`
- Modify: `lib/core/time/clock.dart:14-31`
- Modify: `lib/features/environment/environment_providers.dart:50-53,87`
- Modify: `CLAUDE.md:116` and `docs/architecture.md:123-124`

**Interfaces:**
- Consumes: `JourneyConfig.walkOnlyMaxMeters`, `AppTimings.uiTick`, `AppTimings.minEnvironmentRefreshInterval`
  (`lib/core/config/app_config.dart`).
- Produces: the three providers are gone. `PlannerConfig` and `planDirectBus(..., {PlannerConfig config})` stay.

- [ ] **Step 1: Prove nothing overrides them.**

Run: `git grep -n "plannerConfigProvider\|uiTickIntervalProvider\|environmentRefreshIntervalProvider" -- lib test integration_test tool`
Expected: matches only in the three `lib/` files being edited. If anything else matches, stop and report it.
Don't delete a provider that something uses.

- [ ] **Step 2: Planner.** In `lib/features/journey/journey_providers.dart`, delete:

```dart
/// Planner tunables (defaults: JourneyConfig). Injectable for tests.
final plannerConfigProvider = Provider<PlannerConfig>(
  (ref) => const PlannerConfig(),
);
```

In `journeyPlanProvider`, replace:

```dart
  final config = ref.watch(plannerConfigProvider);
  final direct = WalkEstimate.between(origin, destination);
  if (direct.straightLineMeters <= config.walkOnlyMaxMeters) {
    return WalkOnly(direct);
  }
  final network = await ref.watch(busNetworkProvider.future);
  return planDirectBus(network, origin, destination, config: config);
```

with:

```dart
  final direct = WalkEstimate.between(origin, destination);
  if (direct.straightLineMeters <= JourneyConfig.walkOnlyMaxMeters) {
    return WalkOnly(direct);
  }
  final network = await ref.watch(busNetworkProvider.future);
  return planDirectBus(network, origin, destination);
```

- [ ] **Step 3: UI tick.** In `lib/core/time/clock.dart`, delete:

```dart
/// How often [uiTickProvider] ticks. Injectable for tests.
final uiTickIntervalProvider = Provider<Duration>((ref) => AppTimings.uiTick);

```

and in `UiTick.build`, replace:

```dart
    final timer = Timer.periodic(
      ref.watch(uiTickIntervalProvider),
      (_) => state++,
    );
```

with:

```dart
    final timer = Timer.periodic(AppTimings.uiTick, (_) => state++);
```

- [ ] **Step 4: Refresh cooldown.** In `lib/features/environment/environment_providers.dart`, delete:

```dart
/// Minimum refresh interval, injectable for tests.
final environmentRefreshIntervalProvider = Provider<Duration>(
  (ref) => AppTimings.minEnvironmentRefreshInterval,
);

```

and in `refreshAll()`, replace:

```dart
        now.difference(last) < ref.read(environmentRefreshIntervalProvider) &&
```

with:

```dart
        now.difference(last) < AppTimings.minEnvironmentRefreshInterval &&
```

- [ ] **Step 5: Docs.** In `CLAUDE.md`, replace:

```markdown
`uiTickIntervalProvider` is injectable too; tests keep the real 15 s tick and advance it
  with fake time (`tester.pump(AppTimings.uiTick)`).
```

with:

```markdown
Tests keep the real 15 s UI tick and advance it
  with fake time (`tester.pump(AppTimings.uiTick)`).
```

In `docs/architecture.md`, replace:

```markdown
- Tunables live in `JourneyConfig` / `TransportDataBounds` (`app_config.dart`), injectable via
  `plannerConfigProvider`. Test seams: `busNetworkRepositoryProvider`, `mrtRepositoryProvider`.
```

with:

```markdown
- Tunables live in `JourneyConfig` / `TransportDataBounds` (`app_config.dart`); planner tests pass a
  `PlannerConfig` to `planDirectBus`. Test seams: `busNetworkRepositoryProvider`, `mrtRepositoryProvider`.
```

- [ ] **Step 6: Run the suite.**

Run: `flutter test`
Expected: PASS. If analyze reports an unused import, remove that import.

- [ ] **Step 7: Format, analyze, commit.**

```bash
dart format --set-exit-if-changed .
flutter analyze
git add lib CLAUDE.md docs/architecture.md
git commit -m "refactor: drop providers that nothing overrides (planner config, UI tick, refresh cooldown)"
```

---

### Task 6: Dead parameters and a class that should be a record

**Files:**
- ~~Modify: `lib/app/app_logo.dart:23-45`~~ (void, see Step 1)
- Modify: `lib/features/places/data/onemap_parser.dart:44-72`
- Modify: `lib/core/http/json_http_client.dart:136,146,201-206`
- Modify: `docs/data-sources.md:63`

**Interfaces:**
- Produces: `_typeOf({required String name, required String? building})`. `_Received` is a private record typedef.

- [ ] **Step 1: `AppLogo`. VOID, skip it (#62).** Since E4 the About dialog passes `const AppLogo(size: 48)`
  (`lib/app/about_dialog.dart`), so removing `size` would break the build. Kept only as a record of the
  original step: in `lib/app/app_logo.dart`, replace:

```dart
/// [asset] is cropped to its rounded tile with transparent corners, 192 px
/// square, so it stays sharp up to 6× the default size.
///
/// Decorative: it always sits next to the app title, so screen readers skip it.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 32});

  static const String asset = 'assets/app_icon.png';

  final double size;
```

with:

```dart
/// [asset] is cropped to its rounded tile with transparent corners, 192 px
/// square, so it stays sharp up to 6× [size].
///
/// Decorative: it always sits next to the app title, so screen readers skip it.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key});

  static const String asset = 'assets/app_icon.png';
  static const double size = 32;
```

- [ ] **Step 2: OneMap `BLK_NO`.** In `lib/features/places/data/onemap_parser.dart`, delete the line
  `  final block = _clean(r['BLK_NO']);`, replace
  `    type: _typeOf(name: name, building: building, block: block),` with
  `    type: _typeOf(name: name, building: building),`, and replace:

```dart
PlaceType _typeOf({
  required String name,
  required String? building,
  required String? block,
}) {
```

with:

```dart
PlaceType _typeOf({required String name, required String? building}) {
```

In `docs/data-sources.md`, replace `` `BUILDING` / `BLK_NO` (type inference only) `` with
`` `BUILDING` (type inference only) ``.

- [ ] **Step 3: `_Received` as a record.** In `lib/core/http/json_http_client.dart`, replace:

```dart
class _Received {
  const _Received(this.status, this.headers, this.body);
  final int status;
  final Map<String, String> headers;
  final List<int> body;
}
```

with:

```dart
typedef _Received = ({int status, Map<String, String> headers, List<int> body});
```

Replace `      return _Received(status, response.headers, const []);` with:

```dart
      return (status: status, headers: response.headers, body: const <int>[]);
```

and `    return _Received(status, response.headers, body.takeBytes());` with:

```dart
    return (status: status, headers: response.headers, body: body.takeBytes());
```

Field reads (`response.status`, `response.headers[...]`, `response.body`) stay as they are.

- [ ] **Step 4: Run the suite.**

Run: `flutter test`
Expected: PASS. In particular `test/core/json_http_client_test.dart`, the OneMap parser tests in
`test/features/places/`, and the app-bar tests that find `Key('app-logo')`.

- [ ] **Step 5: Format, analyze, commit.**

```bash
dart format --set-exit-if-changed .
flutter analyze
git add lib/features/places/data/onemap_parser.dart lib/core/http/json_http_client.dart docs/data-sources.md
git commit -m "refactor: drop the unused BLK_NO read; _Received as a record"
```

---

### Task 7: Final gates, run log, PR

**Files:**
- Modify: `docs/testing.md` (append rows to the run-log table at the end of the file)

- [ ] **Step 1: Confirm the cuts are complete.**

Run: `git grep -n "StopArrivalsResult\|StopArrivalsLoaded\|StopArrivalsFailed\|_Checking\|plannerConfigProvider\|uiTickIntervalProvider\|environmentRefreshIntervalProvider\|BLK_NO" -- lib test integration_test CLAUDE.md docs ':!docs/testing.md' ':!docs/simplification-plan.md'`
Expected: no output.

- [ ] **Step 2: Run every gate from CLAUDE.md, and note each start and end time in UTC.**

```bash
dart format --set-exit-if-changed .
flutter analyze
flutter test
flutter build web
flutter build apk --debug
```

Expected: each one passes. Then run the integration tests if a device is available:
`flutter devices`, then `flutter test integration_test -d <android-device-id>`. For the Web run, use the
`flutter drive` command in CLAUDE.md (it needs chromedriver on port 4444). If there's no device or no
chromedriver, don't run it. Log it as **Not run** with that reason.

- [ ] **Step 3: Record the results.** Append one row to the run-log table at the end of `docs/testing.md`, in the
  same `| Date | Milestone | What ran | Result |` format as the rows above it. Give the date in SGT, name the
  branch and commit, and list each command with its time and real result (test counts, pass/fail). Logging a
  gate as passed without running it breaks the evidence rule.

- [ ] **Step 4: Commit, push, open the PR. Don't merge.**

```bash
git add docs/testing.md
git commit -m "docs(testing): gates for the simplification refactor"
git push -u origin refactor/simplify
gh pr create --base main --title "refactor: remove redundant caches, a parallel load type and dead parameters" --body "Implements docs/simplification-plan.md. No behaviour change. Gates: see the new row in docs/testing.md."
```

---

## Self-review notes (for the implementer)

- Tasks 2 and 3 each start with a test that already passes, pinning the current behaviour. If it fails before
  you change any code, your checkout differs from `2772b0a`. Stop and compare.
- If any step's quoted "old" code isn't found, `main` has moved. Find the equivalent code. Don't apply the edit
  somewhere else, and don't skip the step without saying so in the PR.
- Leave the "Left alone" items in the table above alone, even if a tool or reviewer suggests cutting them.
