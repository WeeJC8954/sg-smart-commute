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
| Happy path (fake GPS in SG → dashboard → destination → direct bus + ETA → manual refresh) | Built up across M1–M4 |
| Fallback/error path (permission denied or outside SG → manual origin → provider failure → error + Retry → recovery) | M1, error states extended in M4 |

**chromedriver is not installed** on the Milestone 0 machine. One way to get a version matching Chrome:
`npx @puppeteer/browsers install chromedriver@stable`. Until it's installed, Web integration runs are pending.

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
