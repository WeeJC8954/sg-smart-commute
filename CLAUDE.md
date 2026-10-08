# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Front-end-only Flutter app (Android + Web) for Singapore: environmental dashboard (2-hr forecast, UV, 1-hr
PM2.5, 24-hr PSI), place search, a direct-bus planner with live arrivals, an MRT alternative and, since Phase 2,
an optional journey map. The spec is `docs/singapore-smart-commute-implementation-guide.v2.md` (guide v2.1; code and docs
cite it as `§N`). Decisions live in `docs/architecture.md` (ADRs), tunable values and ambiguity resolutions in
`docs/assumptions.md`, provider details in `docs/data-sources.md`. Work proceeds one milestone at a time
(guide §21: M0 feasibility → M1 location + environment → M2 places → M3 bus planner + MRT → M4 live arrivals
→ M5 hardening → Phase 2 map; Phase 2 closed in P2-M4, and a later change needs its own milestone); don't broaden
scope or start a later milestone silently. After submission, enhancements were added outside the milestones: E1
colour themes (five selectable palettes, `features/appearance/`; plan `docs/e1-colour-themes-implementation-plan.md`),
then E3 app icons and E4 About (plan `docs/enhancement-phase-a-identity-about-implementation-plan.md`).

## Hard constraints (guide §2, §14, ADR-001)

- **No server-side component of any kind** — no backend, proxy, Worker, serverless/Firebase function — not
  for credentials, not for CORS, not as a fallback.
- **No credentials, no secrets.** Everything in the APK/Web bundle is public: no `.env`, `flutter_dotenv`,
  `--dart-define` or asset secrets. A provider that needs a confidential key or blocks browser CORS is out of
  scope (e.g. LTA DataMall, OneMap routing) — replace it with another adapter, never proxy it.
- Non-secret config (endpoints, SG bounds, timeouts, radii, stale thresholds) is Dart constants in
  `lib/core/config/app_config.dart`.
- Never invent readings, arrival times, routes or stops; show a degraded/error state instead.
- data.gov.sg anonymous limit is **6 calls / 10 s**; requests are session-cached and deduplicated, Riverpod
  auto-retry is off, and there is no automatic polling.
- `shared_preferences` (E1) is local only: it keeps the chosen colour palette's id on the device or browser, with no
  host, no CSP change and no secret.
- Record new ambiguity resolutions or tunable values in `docs/assumptions.md`.

## Commands

Toolchain: Flutter 3.47.2 stable (Dart 3.13.2), Android SDK 36 / JDK 21.

```bash
flutter pub get
flutter run -d chrome                 # Web
flutter run -d <device-id>            # Android (emulator default GPS is outside SG — set an SG location)

# Quality gates (guide §19) — all must actually pass; don't suppress lints to go green
dart format --set-exit-if-changed .
flutter analyze
flutter test
flutter build web
flutter build apk --debug
flutter test integration_test -d <android-device-id>

# Single test file / single test by name
flutter test test/features/origin/origin_controller_test.dart
flutter test test/features/origin/origin_controller_test.dart --plain-name "<test name substring>"

# Web integration test, one file per run (needs chromedriver matching Chrome on port 4444). Profile mode on
# web-server: debug-mode drive never starts here (why: docs/testing.md)
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/app_boot_test.dart -d web-server --browser-name=chrome --profile
```

CI (`.github/workflows/flutter-test.yml`, every push and on demand) runs `flutter pub get --enforce-lockfile`, format, analyze and `flutter test` on Ubuntu with Flutter 3.47.2. Windows Smart App Control blocks `flutter_tester.exe` on the development PC, so `flutter test` evidence comes from CI runs, never a claimed local pass.

Dev-only feasibility probes (not part of the app) are in `tool/`; see `docs/testing.md`. Building the probe
APK (`-t tool/api_probe_app.dart`) overwrites `app-debug.apk` — rebuild the real app afterwards.

## Architecture

Feature-first with a pragmatic clean architecture (guide §11):

- `lib/core/` — shared infrastructure: `config/` (constants), `errors/app_failure.dart` (sealed `AppFailure`
  hierarchy, guide §13), `http/json_http_client.dart` (10 s timeout, bounded retry on 5xx/network, no retry on
  4xx, 429 → `ApiRateLimited` with `Retry-After`, in-flight dedup, 4 MiB body cap), `location/` (`LocationService` seam +
  geolocator adapter), `geo/` (`LatLng`, `isWithinSingapore`, haversine), `time/` (injectable `Clock`, SGT
  formatting).
- `lib/features/<feature>/` split into `data/` (DTO parsing + repository implementations), `domain/` (models,
  repository interfaces, pure logic), `presentation/` (widgets). DTOs never reach widgets.
- `lib/app/` — app shell (`SmartCommuteApp` with `ProviderScope(retry: noAutomaticRetry)`) and home screen; the app's
  identity: `AppTitle`/`AppLogo`, and the E4 About action and dialog (`about_dialog.dart`) whose version comes from
  `app_info.dart` (`appInfoProvider`: Flutter's compiled-in `appBuildName`/`appBuildNumber`, no plugin; "Version
  unavailable" when a build has none). Platform icons (E3) are generated from `tool/icon/app_icon_master.png`, never
  edited by hand: `dart pub global run flutter_launcher_icons -f tool/icon/flutter_launcher_icons.yaml` (0.14.4), then
  `dart run tool/icon/maskable_icons.dart` (`docs/testing.md`).

State is Riverpod 3 with `AsyncValue<T>`; errors inside it are typed `AppFailure`s so widgets switch on them (loads go
through `guardAppFailure` in `core/errors/failure_guard.dart`, which also debug-logs the failure detail).
Don't add a parallel `LoadState` type.

Key flows that span several files:

- **Origin** (`features/origin/domain/origin_controller.dart`): a `Notifier` state machine — permission →
  10 s timeout (started only after permission is granted; the permission prompt has its own 10 s bound that falls
  back to manual entry without abandoning the attempt) → GPS fix validated against SG bounds → manual
  fallback. Each acquisition attempt has an id and superseded attempts' results are dropped. **No location
  attempt may replace a manual origin**; a late or retried fix is only offered via the "Use my current
  location" chip (`useCurrentLocation()`). Since M2 the manual origin is a searched place
  (`features/places/`, OneMap), the same search component as the destination. Full rules: the "Late fix"
  row of `docs/assumptions.md`.
- **Environment** (`features/environment/`): `environment_providers.dart` exposes one session-cached
  `FutureProvider` per dataset plus a refresh-all with cooldown; `domain/environment_locator.dart` picks the
  nearest forecast area / PM2.5–PSI region to the origin by haversine; `domain/bands.dart` holds the band
  tables; staleness thresholds and the UV night rule come from `app_config.dart` / `docs/assumptions.md`.
- **Journey** (`features/journey/`): `journeyPlanProvider` watches origin + destination and runs the pure
  `planDirectBus` (zero transfers; 400 → 800 m candidates; shortest valid segment per direction; score
  `walk + walk + 1.5 × stops`) on busrouter data loaded once per session (`busNetworkProvider`). Stops are
  `[lng, lat, name, road]` — converted only in `busrouter_parser.dart`. The MRT alternative uses the bundled
  `assets/mrt_stations.json` (regenerate with `tool/build_mrt_asset.dart`; code-only station names map only
  through the cited table in `mrt_grouping.dart`).
- **Bus arrival** (`features/bus_arrival/`): `journeyArrivalsProvider` runs only after the plan exists and
  requests each displayed boarding stop once through `BusArrivalCache` (15 s TTL, in-flight dedup, failures
  not cached). Its result carries the exact plan it was fetched for, and widgets show it only against that
  plan (no stale attach). ArriveLah JSON is parsed only in `arrivelah_parser.dart`; ETAs come from `time` and
  the clock (`Arr` ≤ 1 min, else minutes rounded down), never `duration_ms`. Refresh never recomputes the plan.
- **Map** (`features/map/`, P2-M1, ride line P2-M2, option sync P2-M3): `mapSceneProvider` turns origin,
  destination, the current `journeyPlanProvider` value, the journey card's selection and the MRT suggestion into a
  pure `MapScene` (the selected option's stops; only the two ends while the plan loads or failed); it never plans or
  selects. The map is closed by default (`mapExpandedProvider`, session UI state), so no
  tile is requested before "Show map". `flutter_map` / `latlong2` are imported only in `features/map/presentation/`.
  OneMap Default/Night tiles, gestures without fling and with an
  instant double-tap zoom under the system's reduce-motion setting (P2-M4), camera fitted before the first frame inside OneMap's bounds and z11–19 and refitted
  once per scene change (journey, selection, MRT settling; never on a timer), no automatic tile retry, persistent linked attribution (`url_launcher`). Rules: `docs/map-feasibility.md` §4.2 and the map
  rows of `docs/assumptions.md`. **Ride line** (P2-M2): the scene carries the selected option's `MapRide`
  (from `BusOption.boardIndex` and `BusService.sourceDirectionOf`); `routeGeometryProvider` loads busrouter
  `routes.min.json` lazily, once per session (nothing before "Show map" with a direct-bus journey; a failure is held
  with no automatic retry and `MapExpanded.show` retries a held failure only when the journey being shown has a bus ride
  (and `ref.exists`), so nothing is requested for a walk-only or no-bus journey);
  the pure `matchRide` draws the line only if **every** ride stop matches in order (all-or-nothing, doubling only
  closed lines), else markers and a note, never a straight stand-in. The camera bounds include the ride's stops.
  Rules: the "Bus ride line" and "Route geometry load" rows of `docs/assumptions.md`. **Option sync** (P2-M3): one
  selection, journey-owned (`optionSelectionProvider`, written by the card's "Select", read by the map), honoured
  only for the identical plan object (`selectedOptionIndex`), so it never carries over to a new journey; selecting
  never re-plans or touches arrivals. **Walk connectors**: `MapScene.walks`, derived from the markers (origin →
  boarding, alighting → destination), straight and dashed, never routed (no walking router: `docs/map-feasibility.md` §6.1). **MRT markers**: read from
  `mrtSuggestionProvider` (settled values only), worded via the journey's `MrtWording`. Rules: the P2-M3 rows of
  `docs/assumptions.md`.
- **Appearance** (`features/appearance/`, post-submission E1): five curated palettes (`domain/app_palette.dart`: Teal
  the default, Blue, Rose, Purple, Orange), each theme generated only by `ColorScheme.fromSeed` from its seed
  (`presentation/palette_theme.dart`, no hand-tuned role); brightness stays the system's. `main()` reads the stored id
  once before `runApp` (`loadInitialPalette`, bounded by `AppearanceConfig.paletteLoadTimeout`, 500 ms; Teal on a
  missing or unknown value, an error or a timeout; a late result is ignored) and passes it as `initialPaletteProvider`.
  `paletteProvider` is the one source of truth: `select` changes it at once and writes the id through `PaletteStore`
  (`shared_preferences`, key `colour_palette`); a failed write is silent and the running app never reads storage again.
  The app-bar `PaletteMenuButton` (a `MenuAnchor` of five `RadioMenuButton`s) only calls `select`. A palette change only
  recolours: map state, camera, plan, arrivals, geometry and selection are kept and no tile is requested
  (`test/features/appearance/palette_change_invariants_test.dart`). Rules: the E1 rows of `docs/assumptions.md`.
- **Time**: parse provider timestamps only with the strict `parseSourceTimestamp` (explicit offset, no
  rolled-over fields; never plain `DateTime.parse`), store UTC, display at a fixed +08:00 offset (no `timezone`
  package).

## Testing

- Test seams overridden via providers: `locationServiceProvider`, `environmentRepositoryProvider`,
  `locationTimeoutProvider`, `locationPermissionTimeoutProvider`, `clockProvider`,
  `placeSearchRepositoryProvider` (plus
  `placeSearchDebounceProvider` / `placeSearchMinQueryLengthProvider`), `busNetworkRepositoryProvider`,
  `mrtRepositoryProvider`, `mrtMaxDistanceMetersProvider`, `busArrivalRepositoryProvider`,
  `busArrivalCacheTtlProvider`, `mapTileProviderFactoryProvider`, `mapLogoImageProvider`, `mapLinkOpenerProvider`,
  `routeGeometryRepositoryProvider` (all faked by default in `buildTestApp`, the last with
  `FakeRouteGeometryRepository`: no test fetches a tile or `routes.min.json`, or opens a browser), `uiMotionDurationProvider` (`buildTestApp` defaults it to zero, so layout changes
  land in one frame; `test/core/motion_test.dart` covers the animated path and `test/app/home_screen_test.dart` the whole app at the real duration). `integration_test/fakes/test_app.dart`
  (`buildTestApp`) builds the real app with all of them faked; the fakes are shared by widget tests and
  `integration_test/`. Widget tests importing `integration_test/fakes/` is a deliberate test-harness
  arrangement required by the Web integration build (see below), not a general `test/` → `integration_test/`
  dependency: the fakes are the only thing `test/` imports from there. `uiTickIntervalProvider` is injectable too; tests keep the real 15 s tick and advance it
  with fake time (`tester.pump(AppTimings.uiTick)`). `paletteStoreProvider` is faked by `FakePaletteStore` in `buildTestApp` (no test touches
  real storage) and `initialPaletteProvider` sets the starting palette (`buildTestApp(paletteStore:, palette:)`).
  `appInfoProvider` is overridden with the fake `fakeAppInfo` (`9.8.7 (42)`, a version no real build has) by default;
  `buildTestApp(appInfo: null)` is a build with no version.
- Integration tests are deterministic and **never call live APIs**; live behaviour is covered by the manual
  smoke tests and probes in `docs/testing.md`.
- NEA parser tests use real payloads captured once in `test/fixtures/*.json`.
- `integration_test/support.dart` has `pumpUntilFound` — use it instead of `pumpAndSettle`, which never
  settles while a progress indicator animates. Use `fake_async` / injected `Clock` for time-dependent logic.
  Every integration test's `main` starts with `initIntegrationTest()` (registers `TestTextInput`, so
  `enterText` works in the profile builds the Web runs use); shared fakes stay under `integration_test/` (Web
  builds cannot import outside it), and nothing else in `test/` should import from `integration_test/`.
- A new provider host must be added to the CSP `connect-src` in `web/index.html`
  (`test/web/content_security_policy_test.dart` checks it against `app_config.dart`).
- Presentation colours come only from `Theme.of(context).colorScheme`; the five palette seeds in `lib/features/appearance/domain/app_palette.dart` are the only fixed colours, and no `Colors.*` is used in `lib/` code (`test/app/app_theme_test.dart` scans `lib/`).
- **Evidence rule:** never claim a test or gate passed unless it actually ran. Record the command and its
  real result in the run log in `docs/testing.md`; anything not run is logged as **Not run** with the reason.

## Git

Small descriptive commits on a feature branch; never commit or push to `main`; merge via PR; no force-push or
history rewrites (guide §23).
