# Testing

Strategy and the full test list: guide v2.1 §18. This file records how to run things and what has run.

## Commands (quality gates)

```bash
dart format --set-exit-if-changed .
flutter analyze
flutter test
flutter build web
flutter build apk --debug
```

## Integration tests (deterministic, fake providers, no live APIs)

The requirements are in guide v2.1 §18. The Phase 1 minimum is one happy-path test and one fallback/error-path
test. Both run the real app with every external provider replaced by a fake, so **no live API is ever
called**. Live API behaviour is covered by the smoke tests and probes below.

```bash
# Android (emulator or device)
flutter test integration_test -d <device-id>

# Web: needs a chromedriver matching your Chrome version, running on port 4444
chromedriver --port=4444 &
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/app_boot_test.dart -d chrome
```

| Test | Status |
|---|---|
| `integration_test/app_boot_test.dart` (harness check) | Milestone 0. See the run log |
| `integration_test/happy_path_test.dart` (fake GPS in SG → dashboard → destination → direct bus + ETA → manual refresh) | M1 portion written (fake GPS → scoped dashboard). Destination/bus/ETA steps come in M2–M4 |
| `integration_test/fallback_path_test.dart` (permission denied or outside SG → manual origin → provider failure → error + Retry → recovery) | Written in M1 (provider failure = 24-hr PSI `NetworkUnavailable`; also out-of-SG and timeout + late-fix cases). Bus-arrival failure added in M4 |

Since M1, `app_boot_test.dart` also uses fake providers (the app now requests location and calls data.gov.sg at
launch). Fakes live in `test/fakes/` and are shared by widget and integration tests. NEA parser tests use real
payloads captured once with curl on 2026-10-01 (`test/fixtures/*.json`).

**chromedriver is not installed** on the Milestone 0 machine. One way to get a version matching Chrome:
`npx @puppeteer/browsers install chromedriver@stable`. Until it's installed, Web integration runs are pending.

## Open acceptance items

- **Web (Chrome) integration test: not run.** chromedriver was not available in Milestone 0, and was still not
  installed in Milestone 1 (`command -v chromedriver` → not found), so no `flutter drive … -d chrome` run has
  happened. The M1 targets are `app_boot_test.dart`, `happy_path_test.dart` and `fallback_path_test.dart`. Run it once chromedriver is available:

  ```bash
  chromedriver --port=4444 &
  flutter drive --driver=test_driver/integration_test.dart \
    --target=integration_test/app_boot_test.dart -d chrome
  ```

  Repeat with `--target=` set to each integration test file as they are added (guide v2.1 §18), and record
  the result in the run log.
- This does **not** block Milestone 1. It is carried forward from M1 and must be closed by Milestone 5 at the latest.
- **M1 app not yet run manually on a device or in Chrome** (smoke tests §18 1–5: Chrome localhost, emulator with
  an SG location, emulator default location, GPS denied, GPS timeout). Only automated tests with fakes ran in M1.
- **Cross-platform integration coverage is not complete** until the Web run has been executed and its
  result recorded below. Until then, integration coverage is Android only.

## Evidence rule

Record the actual command and its actual result in the run log. Never claim a test or gate passes unless it
was executed. A test that was not run is logged as **Not run**, with the reason.

## Feasibility probes (Milestone 0, no credentials)

```bash
bash tool/probe_apis.sh                         # curl: status + CORS headers
dart run tool/place_search_eval.dart            # 51-query place-search evaluation
flutter run -d chrome -t tool/api_probe_app.dart   # real browser (CORS enforced)
flutter build apk --debug -t tool/api_probe_app.dart && adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

Note: building the probe APK replaces `app-debug.apk`. Rebuild the real app afterwards with
`flutter build apk --debug`.

## Android emulator notes

- AVD used: `Pixel_8_Pro`. Its default GPS location is **outside Singapore** (Mountain View), which the app
  must treat as unavailable. For "GPS success" tests, set a Singapore location (Extended controls →
  Location, e.g. 1.3508, 103.8485).
- If `flutter run` hangs at launch (black screen / adb timeout), cold-boot the emulator:
  `emulator -avd Pixel_8_Pro -no-snapshot-load`.

## Run log

| Date | Milestone | What ran | Result |
|---|---|---|---|
| 2026-10-01 | M0 | `dart format --set-exit-if-changed .` | Pass (the first run reformatted 3 files, which were fixed) |
| 2026-10-01 | M0 | `flutter analyze` | Pass, no issues (the first run had 4 `curly_braces_in_flow_control_structures` infos in `tool/`, fixed) |
| 2026-10-01 | M0 | `flutter test` | Pass, 1/1 (skeleton widget test) |
| 2026-10-01 | M0 | `flutter build web` | Pass (Wasm dry run succeeded; informational notice only) |
| 2026-10-01 | M0 | `flutter build apk --debug` | Pass |
| 2026-10-01 | M0 | `flutter test integration_test -d emulator-5554` | Pass, 1/1 (`app_boot_test`, Pixel 8 Pro AVD) |
| 2026-10-01 | M0 | Web integration test (`flutter drive … -d chrome`) | **Not run**: chromedriver not installed |
| 2026-10-01 | M0 | API probes: curl, Chrome, Android | All selected providers 200. LTA DataMall CORS-blocked in Chrome |
| 2026-10-01 | M0 | Place-search eval (51 queries) | See `api-feasibility.md` §4 |
| 2026-10-01 | M0 cleanup | `flutter analyze` (after adding INTERNET to the main manifest) | Pass, no issues |
| 2026-10-01 | M0 cleanup | `flutter build apk --release` | Pass. Merged release manifest contains `android.permission.INTERNET`. APK not run on a device |
| 2026-10-01 | M0 / PR #2 post-merge (main @ 0d5cf66, run by the main session) | `flutter test` | Pass, 1 test ("All tests passed!") |
| 2026-10-01 | M0 / PR #2 post-merge (main @ 0d5cf66, run by the main session) | `flutter build apk --release` + `adb install -r` on emulator-5554 (API 37) | Success. `dumpsys package` shows `android.permission.INTERNET: granted=true` |
| 2026-10-01 | M0 / PR #2 post-merge (main @ 0d5cf66, run by the main session) | Temporary uncommitted probe (dart:io `HttpClient` GET data.gov.sg `/uv`) in a release APK | logcat `NETPROBE status=200`. Details: PR #2 comment 5931287026 |
| 2026-10-01 | M1 | `curl` once per NEA dataset (two-hr-forecast, uv, pm25, psi) to capture `test/fixtures/` | 4 × 200 (4 calls, within the 6 / 10 s limit) |
| 2026-10-01 | M1 | `flutter test` before implementation (TDD red run) | Fail as expected: 7 test files failed to load (missing implementation) |
| 2026-10-01 | M1 | `dart format lib test integration_test` | Formatted; run before each commit |
| 2026-10-01 | M1 | `flutter analyze` | Pass, no issues (earlier runs flagged `curly_braces_in_flow_control_structures` infos, fixed) |
| 2026-10-01 | M1 | `flutter test` | Pass, 94/94 (unit + widget) |
| 2026-10-01 | M1 | `flutter test integration_test -d emulator-5554` (sdk gphone16k x86 64, Android 17 / API 37) | Pass, 5/5 (`app_boot` 1, `fallback_path` 3, `happy_path` 1), fake providers only |
| 2026-10-01 | M1 | Web integration test (`flutter drive … -d chrome`) | **Not run**: chromedriver not installed |
| 2026-10-01 | M1 | `flutter build web` | Pass (Wasm dry run succeeded; informational notice only) |
| 2026-10-01 | M1 | `flutter build apk --release` | Pass (48.3 MB; Gradle/javac warnings only, no errors). Release APK not run on a device in M1 |
