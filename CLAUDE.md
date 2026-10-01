# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Front-end-only Flutter app (Android + Web) for Singapore: environmental dashboard (2-hr forecast, UV, 1-hr
PM2.5, 24-hr PSI) and, in later milestones, place search, a direct-bus planner with live arrivals, and an MRT
alternative. The spec is `docs/singapore-smart-commute-implementation-guide.v2.md` (guide v2.1; code and docs
cite it as `§N`). Decisions live in `docs/architecture.md` (ADRs), tunable values and ambiguity resolutions in
`docs/assumptions.md`, provider details in `docs/data-sources.md`. Work proceeds one milestone at a time
(guide §21: M0 feasibility → M1 location + environment → M2 places → M3 bus planner + MRT → M4 live arrivals
→ M5 hardening → Phase 2 map); don't broaden scope or start a later milestone silently.

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

# Web integration test (needs chromedriver matching Chrome on port 4444)
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/app_boot_test.dart -d chrome
```

Dev-only feasibility probes (not part of the app) are in `tool/`; see `docs/testing.md`. Building the probe
APK (`-t tool/api_probe_app.dart`) overwrites `app-debug.apk` — rebuild the real app afterwards.

## Architecture

Feature-first with a pragmatic clean architecture (guide §11):

- `lib/core/` — shared infrastructure: `config/` (constants), `errors/app_failure.dart` (sealed `AppFailure`
  hierarchy, guide §13), `http/json_http_client.dart` (10 s timeout, bounded retry on 5xx/network, no retry on
  4xx, 429 → `ApiRateLimited` with `Retry-After`, in-flight dedup), `location/` (`LocationService` seam +
  geolocator adapter), `geo/` (`LatLng`, `isWithinSingapore`, haversine), `time/` (injectable `Clock`, SGT
  formatting).
- `lib/features/<feature>/` split into `data/` (DTO parsing + repository implementations), `domain/` (models,
  repository interfaces, pure logic), `presentation/` (widgets). DTOs never reach widgets.
- `lib/app/` — app shell (`SmartCommuteApp` with `ProviderScope(retry: noAutomaticRetry)`) and home screen.

State is Riverpod 3 with `AsyncValue<T>`; errors inside it are typed `AppFailure`s so widgets switch on them.
Don't add a parallel `LoadState` type.

Key flows that span several files:

- **Origin** (`features/origin/domain/origin_controller.dart`): a `Notifier` state machine — permission →
  10 s timeout (started only after permission is granted) → GPS fix validated against SG bounds → manual
  fallback. Each acquisition attempt has an id and superseded attempts' results are dropped. **No location
  attempt may replace a manual origin**; a late or retried fix is only offered via the "Use my current
  location" chip (`useCurrentLocation()`). In M1 the manual origin is a pick from the NEA forecast areas
  (place search arrives in M2). Full rules: the "Late fix" row of `docs/assumptions.md`.
- **Environment** (`features/environment/`): `environment_providers.dart` exposes one session-cached
  `FutureProvider` per dataset plus a refresh-all with cooldown; `domain/environment_locator.dart` picks the
  nearest forecast area / PM2.5–PSI region to the origin by haversine; `domain/bands.dart` holds the band
  tables; staleness thresholds and the UV night rule come from `app_config.dart` / `docs/assumptions.md`.
- **Time**: parse ISO `+08:00` timestamps, store UTC, display at a fixed +08:00 offset (no `timezone`
  package).

## Testing

- Test seams overridden via providers: `locationServiceProvider`, `environmentRepositoryProvider`,
  `locationTimeoutProvider`, `clockProvider`. `test/fakes/test_app.dart` (`buildTestApp`) builds the real app
  with all of them faked; the fakes are shared by widget tests and `integration_test/`.
- Integration tests are deterministic and **never call live APIs**; live behaviour is covered by the manual
  smoke tests and probes in `docs/testing.md`.
- NEA parser tests use real payloads captured once in `test/fixtures/*.json`.
- `integration_test/support.dart` has `pumpUntilFound` — use it instead of `pumpAndSettle`, which never
  settles while a progress indicator animates. Use `fake_async` / injected `Clock` for time-dependent logic.
- **Evidence rule:** never claim a test or gate passed unless it actually ran. Record the command and its
  real result in the run log in `docs/testing.md`; anything not run is logged as **Not run** with the reason.

## Git

Small descriptive commits on a feature branch; never commit or push to `main`; merge via PR; no force-push or
history rewrites (guide §23).
