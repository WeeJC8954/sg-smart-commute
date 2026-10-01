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
  happened. Still not installed in Milestone 2 (`command -v chromedriver` → not found, `where chromedriver` → not found; nothing was installed). The
  targets are `app_boot_test.dart`, `happy_path_test.dart` and `fallback_path_test.dart` (extended in M2 with
  place search). Run them once chromedriver is available:

  ```bash
  chromedriver --port=4444 &
  flutter drive --driver=test_driver/integration_test.dart \
    --target=integration_test/app_boot_test.dart -d chrome
  ```

  Repeat with `--target=` set to each integration test file as they are added (guide v2.1 §18), and record
  the result in the run log.
- This does **not** block Milestone 1. It is carried forward from M1 and must be closed by Milestone 5 at the latest.
- **Manual smoke tests (§18), partly done.**
  - Done: item 2 (Android emulator with an SG location, real geolocator, live data.gov.sg) in M1.
  - Done in M2, on the Android emulator, recorded in the run log:
    - item 4 (GPS denied, via the real permission dialog → manual prompt);
    - item 6 (postal-code origin, `098585`, live OneMap);
    - item 7 (mall destination, ION Orchard, live OneMap).
  - Still not run: 1 (Chrome localhost), 3 (emulator default location, outside SG) and 5 (GPS timeout) on a real
    device or browser. These are covered only by automated tests with fakes. Items 8–10 need M3–M4 features.
- **Android timeout runs while the system "Location Accuracy" prompt is open (observed in M1, not fixed).** On a
  device where Location Accuracy is off, the geolocator request shows this Google Play services prompt. The 10 s
  timeout keeps running while it is on screen, so a first-time user can land on "Finding your location took too
  long" before answering it. The fallback itself is correct, and "Try location again" then succeeded. In that
  session, the first attempt's request never delivered a late fix (cause not confirmed on the device). To be decided
  by the reviewer: fix it, or leave it as an accepted limitation.
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
| 2026-10-01 | M1 race fix (PR #3 review) | New overlapping-attempt tests against the old controller (red run) | Fail as expected: 5 failures (4 controller + 1 widget, all "retry with manual origin"). The stale-attempt tests (c)/(d) already passed |
| 2026-10-01 | M1 race fix (PR #3 review) | `dart format lib test integration_test`, `flutter analyze` | Formatted 2 files; analyze passes, no issues |
| 2026-10-01 | M1 race fix (PR #3 review) | `flutter test` | Pass, 103/103 |
| 2026-10-01 | M1 race fix (PR #3 review) | `flutter test integration_test -d emulator-5554` | **Not run**: no emulator was running (`flutter devices` listed no Android device) |
| 2026-10-01 | M1 race fix (PR #3 review, re-run by the main session on ed44d63) | `flutter analyze`; `flutter test` | Pass, no issues; pass, 103/103 |
| 2026-10-01 | M1 race fix (PR #3 review, re-run by the main session on ed44d63) | `flutter test integration_test -d emulator-5554` (API 37) | Pass, 5/5 (fake providers) |
| 2026-10-01 | M1 real Android smoke (§18 item 2), run 1, release APK @ ed5085d | Emulator API 37, GPS set by `adb emu geo fix 103.8510 1.2840` (Raffles Place); real geolocator; live data.gov.sg | Android permission dialog → "While using the app". Google "Location Accuracy" prompt appeared; the app's 10 s timeout fired while it was open → "Finding your location took too long" + manual picker (UV tile already live). Tapped "Turn on", then "Try location again" → "From: Current location (from GPS)". Four live tiles: 2-hr forecast Cloudy, City area, as of 21:06 SGT; UV "not measured at night", last UV 0 (Low) 19:00 SGT, national; 1-hr PM2.5 36 µg/m³ (Normal), South region, 21:00 SGT; 24-hr PSI 72 (Moderate), South region, 21:00 SGT. Cold relaunch (permission granted): GPS accepted on the first attempt, same four tiles |
| 2026-10-01 | M1 real Android smoke (§18 item 2), run 2, release APK @ ed44d63 (race fix) | Fresh install (`adb uninstall` + `adb install`), same SG fix, real geolocator, live data.gov.sg | Permission dialog → "While using the app" → GPS accepted as Singapore on the first attempt ("From: Current location (from GPS)"). All four live tiles rendered with scope + SGT timestamp + age (same values as run 1). Location Accuracy was already on device-wide from run 1, so that prompt did not appear |
| 2026-10-01 | M1 first-time permission flow (PR #3 review), release APK @ ed44d63 (app code identical at 2435d81) | Fresh install (`adb uninstall` + `adb install`; FINE_LOCATION not granted), SG fix via `adb emu geo fix 103.8510 1.2840`, real geolocator, live data.gov.sg. Launched 21:39:54.8 SGT, left the Android permission dialog open, tapped "While using the app" at 21:40:42.0 (~47 s, well over the 10 s timeout) | Pass. Screenshots at +17 s and +46 s after launch: dialog still open, card still "Checking location permission…", no timeout and no manual prompt. After Allow (`ACCESS_FINE_LOCATION: granted=true`): "From: Current location (from GPS)", never in manual-origin mode. Four live tiles: Cloudy, City area (as of 21:36 SGT); UV not measured at night, national; 1-hr PM2.5 36 µg/m³ Normal, South; 24-hr PSI 72 Moderate, South. Consistent with the code: the 10 s timer is created in `_start()` only after `requestAccess()` returns `granted`. Not measured here: the length of the post-Allow window, because the SG fix arrived within seconds |
| 2026-10-01 | M1 data.gov.sg rate limiter (PR #3 code review) | Red run: `flutter test test/features/environment/data_gov_sg_rate_limit_widget_test.dart` on the pre-fix code (only the HTTP transport faked; the fake server enforces 6 / 10 s → 429) | Fail as expected, 3/3: launch + Refresh all at 3 s sent 8 (expected 6); tile Retry sent the 7th call at once (7, expected 6); area-picker Retry likewise (7, expected 6). The first picker run failed with a test bug (a lazy list unbuilt the origin card after scrolling), fixed with a tall test screen before this red run. The limiter and client unit tests use the new API, so they could not run on the pre-fix code |
| 2026-10-01 | M1 data.gov.sg rate limiter | `dart format --set-exit-if-changed .` | Pass, exit 0 (45 files, 0 changed) |
| 2026-10-01 | M1 data.gov.sg rate limiter | `flutter analyze` | Pass, no issues (the first run flagged `prefer_initializing_formals` and an unused test import, both fixed) |
| 2026-10-01 | M1 data.gov.sg rate limiter | `flutter test` | Pass, 117/117 (103 earlier + 14 new: 3 UI-path, 6 limiter, 5 client) |
| 2026-10-01 | M1 data.gov.sg rate limiter | `flutter test integration_test -d emulator-5554` (API 37) | Pass, 5/5 (fake providers) |
| 2026-10-01 | M1 data.gov.sg rate limiter | `flutter build web` | Pass (`✓ Built build\web`) |
| 2026-10-01 | M1 data.gov.sg rate limiter | `flutter build apk --release` | Pass (48.3 MB) |
| 2026-10-01 | M1 data.gov.sg rate limiter, live sanity check | Release APK, fresh install, location pre-granted (`pm grant`), SG fix, live data.gov.sg. Launched 22:28:05 SGT, tapped Refresh all at 22:28:09 | All four tiles rendered by 22:28:29 (Cloudy, City area, 22:06; UV night, national; PM2.5 35 µg/m³ Normal, South; PSI 73 Moderate, South). No "data service is busy" error. Not observable here: the queued sends themselves, and whether the tap registered (no screen confirmation). The exact behaviour is proven by the deterministic tests above, not by this run |
| 2026-10-01 | M2 places | `curl` probes of OneMap (tokenless, `Origin: http://localhost:5000`) | Search `238801`: HTTP 200, `Access-Control-Allow-Origin: *`, body has `error: "Authentication token missing…"` + 1 result. Reverse geocode `/api/public/revgeocode?location=1.2840,103.8510`: **HTTP 401** `{"message":"Unauthorized"}` → not used |
| 2026-10-01 | M2 places | `curl` once per query, ~1 s apart, to capture `test/fixtures/onemap/` | 8 × HTTP 200: `238801` (1), `098585` (1), `123 Ang Mo Kio Avenue 6` (2), raw `Blk 123 Ang Mo Kio Ave 6` (**0**), `VivoCity` (2), `Orchard Road` (9), `Bishan MRT` (8, first has `POSTAL: "NIL"`), `000000` (0). Every body carries the `error` field, including the empty ones |
| 2026-10-01 | M2 places | Mutation check: `place_search_session.dart` sequence-token guard disabled, then `flutter test test/features/places/place_search_session_test.dart`; guard restored | With the guard disabled, 3 tests failed as expected: both race tests and `clear() drops an in-flight response`. Guard restored: 9/9 pass. The other M2 tests were written alongside the code, not as a separate red run |
| 2026-10-01 | M2 places | First run of the migrated M1 widget tests | 3 failed: test harness only. After scrolling to a result and selecting it, the lazy home list left the origin card unbuilt. Fixed with a tall test screen (`pumpApp`); a debug run confirmed the same tap sets the origin. Then 13/13 pass |
| 2026-10-01 | M2 places | Removed `data_gov_sg_rate_limit_widget_test.dart` → "the area picker Retry…" | The M1 area picker no longer exists (replaced by place search), so that path is gone. The launch + Refresh all and tile Retry tests remain |
| 2026-10-01 | M2 places | Release APK, Android emulator API 37, GPS origin (Raffles Place), live OneMap via the destination field. One query per fresh app start | `238801` → ION ORCHARD (1 match). `Blk 123 Ang Mo Kio Ave 6` → 2 matches (`123 ANG MO KIO AVENUE 6 SINGAPORE 560123`, Asian Women's Welfare Assoc. home), so the `Blk` normalisation works live. `VivoCity` → VIVOCITY + VIVOCITY STATION (S1), told apart by address/postcode. `Orchard Road` → 9 matches. `Singapore Botanic Gardens` → 10 matches. Nothing was auto-selected; the attribution showed under each list. The first two attempts were invalid because of how the device was driven (field not cleared / tapped before the card existed) and were redone |
| 2026-10-01 | M2 places | Release APK (fresh install), real permission dialog → **Don't allow** (§18 item 4), live OneMap + data.gov.sg | Immediately "We couldn't determine your location…" + search field. Origin `098585` → tap → "From: VIVOCITY (chosen manually)" + address; the tiles switched to Bukit Merah area / South region (§18 item 6). Destination `Singapore Botanic Gardens` → tap → "To: SINGAPORE BOTANIC GARDENS". Change → `ION Orchard` → tap → "To: ION ORCHARD" (§18 item 7, mall destination). The origin stayed VIVOCITY throughout |
| 2026-10-01 | M2 places | `dart format --set-exit-if-changed .` | Pass, exit 0 (59 files, 0 changed) |
| 2026-10-01 | M2 places | `flutter analyze` | Pass, no issues (earlier runs flagged a factory/field name clash, `prefer_initializing_formals` and an unused import, all fixed) |
| 2026-10-01 | M2 places | `flutter test` | Pass, 168/168 (6 query, 25 OneMap parser/repository, 9 session, 12 M2 widget, plus the existing suites; 1 obsolete picker test removed) |
| 2026-10-01 | M2 places | `flutter test integration_test -d emulator-5554` (API 37) | Pass, 5/5 (fake providers only). Happy path now: fake SG GPS → dashboard → search/select destination. Fallback path now: denied → search/select origin → search/select destination → PSI failure → Retry |
| 2026-10-01 | M2 places | `flutter build web` | Pass |
| 2026-10-01 | M2 places | `flutter build apk --release` | Pass (48.4 MB) |
| 2026-10-01 | M2 places | `flutter build apk --debug` | Pass |
| 2026-10-01 | M2 places | Web integration test (`flutter drive … -d chrome`) | **Not run**: chromedriver not installed (`command -v chromedriver` → not found) |
| 2026-10-02 | M2 PR #5 review fix (`PlaceSearchConfig`) | Mutation checks on `test/features/places/place_search_config_test.dart`, each restored afterwards: (1) the search field no longer passes the provider's debounce (falls back to the 350 ms default); (2) the repository checks a hard-coded minimum of 3 instead of its injected value | Each caught by its target test: (1) `search field: overridden debounce and minimum are used`; (2) `repository minimum length: below it, no request is made`. Restored: 8/8 pass |
| 2026-10-02 | M2 PR #5 review fix | `dart format --set-exit-if-changed .` | Pass, exit 0 (60 files, 0 changed) |
| 2026-10-02 | M2 PR #5 review fix | `flutter analyze` | Pass, no issues (first run flagged an unused import and the removed `minPlaceQueryLength` alias in a test; both fixed) |
| 2026-10-02 | M2 PR #5 review fix | `flutter test` | Pass, 176/176 (168 earlier + 8 new config tests) |
| 2026-10-02 | M2 PR #5 review fix | `flutter test integration_test -d emulator-5554` (API 37) | Pass, 5/5 |
| 2026-10-02 | M2 PR #5 review fix | `flutter build web` | Pass |
| 2026-10-02 | M2 PR #5 review fix | `flutter build apk --release` | Pass (48.4 MB). On 2026-10-01 the same build and the integration run had failed in Gradle with `FileLock.writeFile … is null` (a cache lock; repositories were reachable). They were not re-run until the lock had cleared between sessions, and no Gradle processes were stopped by the agent |
| 2026-10-02 | M3 bus planner | Red run: `flutter test test/features/journey/direct_bus_planner_test.dart` before the planner existed | Fail as expected: compile errors, `direct_bus_planner.dart` not found / `JourneyPlan`, `BusOption` undefined. Four expectation errors in the new tests were found by hand-checking every value before implementing (a wrong "toward" name, an o == d case that still had a valid pair, a tie test that never exercised "fewer stops", and a walk value exactly on a `ceil` boundary) and fixed. Then 26/26 pass |
| 2026-10-02 | M3 bus planner | `flutter test test/features/journey/busrouter_test.dart`, first run | 1 failure, a test-expectation error: on loop 4, stop 76231 has its opposite-side stop 76239 29.1 m away, on the return leg, 5 stops from Tampines Int instead of 22. The planner correctly chose 76239. The route-order tests now use a 10 m "exact stop" radius, plus a test recording this real case. Then 21/21 pass |
| 2026-10-02 | M3 MRT asset | `dart run tool/build_mrt_asset.dart` (live download), then twice with `--input <saved geojson> --retrieved 2026-10-01` | 613 features, 0 skipped, 613 exits, 0 duplicates → 188 stations; 7 code-only mapped, 0 unverified. Both `--input` builds byte-identical (`cmp`), and identical to the live build |
| 2026-10-02 | M3 code-only MRT records | OneMap (tokenless) searched by candidate station name, results compared with the code-only exits | All 7 verified: an exact code label within 41–85 m (CC9 Paya Lebar 69 m, DT18 Telok Ayer 85 m, DT4 Hume 58 m, NE18 Punggol Coast 60 m, CC30 Keppel 50 m, CC31 Cantonment 75 m, CC32 Prince Edward Road 41 m) |
| 2026-10-02 | M3 journey widget tests | First run of `test/features/journey/journey_widget_test.dart` | 3 failures: (1) the bus data load count was 2 after a destination change, because the fake repository has no cache, so session caching depended on the implementation. Fixed by adding `busNetworkProvider` to hold the network for the session. (2–3) a test finder bug: text searched inside a keyed `Text`. Then 10/10 pass |
| 2026-10-02 | M3 | `dart format --set-exit-if-changed .` | Pass, exit 0 (78 files, 0 changed) |
| 2026-10-02 | M3 | `flutter analyze` | Pass, no issues |
| 2026-10-02 | M3 | `flutter test` | Pass, 247/247 (176 from M1/M2, all still passing, plus 71 new: 26 planner, 21 busrouter/real-route, 14 MRT, 10 journey widget) |
| 2026-10-02 | M3 | `flutter build web` | Pass |
| 2026-10-02 | M3 | `flutter build apk --release` | Pass (48.5 MB) |
| 2026-10-02 | M3 | `flutter test integration_test -d emulator-5554` | **Not run yet (environment)**: the APK built, but `adb install` failed with `cmd: Can't find service: package`. The emulator (up 6.5 h, load average 8–15) reported boot completed, while its package service flapped between found and not found. The agent did not restart it; the user is restarting it |
| 2026-10-02 | M3 real-data smoke | `dart run tool/journey_smoke.dart` (live busrouter: 5,208 stops / 602 services; OneMap geocoding, first result; bundled MRT asset). Every option cross-checked against the raw `services.min.json` | **Direct:** Tampines Int → VivoCity: Bus 10 toward Kent Ridge Ter (75009 → 14141 HarbourFront Stn/Vivocity, 52 stops, score 82), alternative Bus 65 (64 stops). **Multiple:** ION Orchard → Bugis Junction: Bus 7 toward Bedok Int and Bus 175 toward Lor 1 Geylang Ter, both 09048 Orchard Stn/Lucky Plaza → 01112 Opp Bugis Stn Exit C, 7 stops, score 16.5 (tie → number). **No direct bus:** Changi Village → "Jurong Point" (OneMap's first result was Family Point Clinic, Taman Jurong; the mall was not checked): No direct bus at 800 m; nearest MRT at the origin: none within 1.5 km. **Loop:** Tampines Int → 390 Tampines Ave 7: Bus 4 (loop), alternatives 19 and 37 (loops), 75009 → 76231, 5 stops. **Walk:** ION Orchard → Wisma Atria: walk only, ~3 min (est.), 134 m. **Cross-check:** all 9 options OK. **Not verified:** completeness (whether a valid service was missed), and real-world timetable or operation |
| 2026-10-02 | M3 OneMap behaviour | The same smoke run | OneMap answered **HTTP 429** after 3 geocoding calls within a few seconds. The script now spaces calls ~3 s apart and backs off on 429. In the app, place search is debounced and a 429 shows as `ApiRateLimited` ("busy, retry"). Recorded as a risk |
