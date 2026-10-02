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
| `integration_test/happy_path_test.dart` (fake GPS in SG → dashboard → destination → direct bus + ETA → manual refresh) | Complete since M4: fake GPS → scoped dashboard → destination → direct bus → live ETA → manual refresh after the cache TTL shows new ETAs |
| `integration_test/fallback_path_test.dart` (permission denied or outside SG → manual origin → provider failure → error + Retry → recovery) | Written in M1 (provider failure = 24-hr PSI `NetworkUnavailable`; also out-of-SG and timeout + late-fix cases). M4 adds: origin with a direct bus → bus-arrival `NetworkUnavailable` (route kept, unavailable + Retry) → recovery → ETA |

Since M1, `app_boot_test.dart` also uses fake providers (the app now requests location and calls data.gov.sg at
launch). Fakes live in `integration_test/fakes/` and are shared by widget and integration tests. NEA parser tests use real
payloads captured once with curl on 2026-10-01 (`test/fixtures/*.json`).

**chromedriver is not installed** on the Milestone 0 machine. One way to get a version matching Chrome:
`npx @puppeteer/browsers install chromedriver@stable`. Until it's installed, Web integration runs are pending.

## Open acceptance items

- **Web (Chrome) integration test: not run.** chromedriver was not available in Milestone 0, and was still not
  installed in Milestone 1 (`command -v chromedriver` → not found), so no `flutter drive … -d chrome` run has
  happened. Still not installed in Milestone 2 (`command -v chromedriver` → not found, `where chromedriver` → not found; nothing was installed), nor in Milestone 4 (`command -v chromedriver` → not found). The
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
    device or browser. These are covered only by automated tests with fakes. Item 1 was attempted in M4 with the
    release web build: the app waited on Chrome's unanswered location prompt with no manual origin offered (see the
    run log), so item 1 stays open. Issue #9 (permission-prompt timeout → manual origin) fixes that trap in code
    and is covered by unit and widget tests with fakes; a live Chrome re-run of item 1 has not been done yet.
  - Done in M3, on the Android emulator with the release APK and live data, recorded in the run log: item 9 (no
    direct bus: Changi Village Bus Terminal → Jurong Point). Item 8 was **partly** done in M3 (direct-bus
    suggestion only).
  - Done in M4, on the Android emulator with the release APK and live ArriveLah, recorded in the run log: the
    live-ETA part of item 8 (Raffles Place → VivoCity, ETAs compared with raw ArriveLah responses, manual refresh)
    and item 10 (provider unavailable: emulator offline → arrivals unavailable + Retry, route kept → recovered).
    Also checked: a missing live arrival (Bus 651 off-peak → "No live arrival available").
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
| 2026-10-02 | M3 | `flutter test integration_test -d emulator-5554` @ f0a1ebc, after a cold boot of the emulator (`-no-snapshot-load`) | **Pass, 5/5** (app boot 1, fallback path 3, happy path 1; 3 min). An earlier attempt the same day could not install the APK (`cmd: Can't find service: package`: the long-running emulator's package service flapped). That was an environment failure, not a test failure; it did not recur after the cold boot |
| 2026-10-02 | M3 real-data smoke | `dart run tool/journey_smoke.dart` (live busrouter: 5,208 stops / 602 services; OneMap geocoding, first result; bundled MRT asset). Every option cross-checked against the raw `services.min.json` | **Direct:** Tampines Int → VivoCity: Bus 10 toward Kent Ridge Ter (75009 → 14141 HarbourFront Stn/Vivocity, 52 stops, score 82), alternative Bus 65 (64 stops). **Multiple:** ION Orchard → Bugis Junction: Bus 7 toward Bedok Int and Bus 175 toward Lor 1 Geylang Ter, both 09048 Orchard Stn/Lucky Plaza → 01112 Opp Bugis Stn Exit C, 7 stops, score 16.5 (tie → number). **No direct bus:** Changi Village → "Jurong Point" (OneMap's first result was Family Point Clinic, Taman Jurong; the mall was not checked): No direct bus at 800 m; nearest MRT at the origin: none within 1.5 km. **Loop:** Tampines Int → 390 Tampines Ave 7: Bus 4 (loop), alternatives 19 and 37 (loops), 75009 → 76231, 5 stops. **Walk:** ION Orchard → Wisma Atria: walk only, ~3 min (est.), 134 m. **Cross-check:** all 9 options OK. **Not verified:** completeness (whether a valid service was missed), and real-world timetable or operation |
| 2026-10-02 | M3 OneMap behaviour | The same smoke run | OneMap answered **HTTP 429** after 3 geocoding calls within a few seconds. The script now spaces calls ~3 s apart and backs off on 429. In the app, place search is debounced and a 429 shows as `ApiRateLimited` ("busy, retry"). Recorded as a risk |
| 2026-10-02 | M3 real-data smoke, rerun with chosen places | `dart run tool/journey_smoke.dart` @ f0a1ebc (each place is the OneMap result with an exact name + postcode, not the first result) | Same results as the first run for Direct, Multiple, Loop and Walk. **No direct bus, now with confirmed places:** MARKET & HAWKER CENTRE (BLKS 2 & 3 CHANGI VILLAGE ROAD) (500002, result 7 of 9) → JURONG POINT (648886, result 3 of 5): no direct bus at 800 m; raw check OK (18 origin / 41 destination stops, no raw route connects them). Nearest MRT at the origin: none within 1.5 km (raw nearest exit 3,552 m); at the destination: Boon Lay Exit C, 114 m. All nearest-MRT results agree with a brute-force pass over the raw asset. No OneMap 429 with the ~3 s spacing |
| 2026-10-02 | M3 on-device smoke (§18 item 8, direct-bus part) | Release APK @ f0a1ebc (`flutter build apk --release`, 48.5 MB) on emulator-5554, `adb emu geo fix 103.8514 1.2840` (Raffles Place), real geolocator, live busrouter / OneMap / data.gov.sg | Permission dialog → "While using the app" → "From: Current location (from GPS)", all four tiles live. Destination search "VivoCity" → VIVOCITY (098585). The journey card showed: ~4 min walk (est.) to 03019 OUE Bayfront, **Bus 10 toward Kent Ridge Ter**, 9 stops, alight 14141 HarbourFront Stn/Vivocity, ~3 min walk; alternatives Bus 57 and Bus 100 (same stops, 9 stops); "Live bus arrival times are not available yet."; MRT: Raffles Place ~1 min, HarbourFront ~2 min. **Raw cross-check:** 10, 57, 100 and 131 all run 03019 → 14141 in 9 stops (131 is cut by `maxOptions` = 3 after the service-number tie-break). 03059 One Raffles Quay is 8 stops but 321 m away: score 6 + 3 + 12 = 21 against 4 + 3 + 13.5 = 20.5 for 03019, so 03019 is correct. The live ETA part of item 8 is M4 |
| 2026-10-02 | M3 on-device smoke (§18 item 9) | Same install. Origin changed by search: "Changi Village" → CHANGI VILLAGE BUS TERMINAL (chosen manually); destination VivoCity, then "Jurong Point" → JURONG POINT (648886; OneMap's first result was still the Taman Jurong clinic, so it was not picked) | Both pairs: "No direct bus found. No single bus connects stops within 800 m of both ends. See the MRT option below."; "Nearest MRT: none within about 1.5 km"; near the destination HarbourFront ~2 min, then Boon Lay ~2 min. **Raw cross-check** (terminal at OneMap 1.38954, 103.98766): VivoCity 17 origin / 10 destination stops within 800 m, Jurong Point 17 / 41, and no raw route connects them in either case; nearest MRT exit to the origin is 3,594 m away (Changi Airport Exit B). No fabricated route was shown |
| 2026-10-02 | M3 gates @ f0a1ebc (before push) | `dart format --set-exit-if-changed .`; `flutter analyze`; `flutter test` | Pass: exit 0 (79 files, 0 changed); no issues; 247/247 |
| 2026-10-02 | M3 review cleanup (chore/m3-review-cleanup) | `flutter test test/features/journey`, first run of the new MRT-text tests | 4 failures, a test finder bug: `inKey` searched *below* the keyed `Text`, but the key sits on that `Text`. Switched to reading the keyed `Text` directly. Then 79/79 pass |
| 2026-10-02 | M3 review cleanup | Mutation check: `journey_card.dart` temporarily put back to the hard-coded `none within about 1.5 km`, then `flutter test test/features/journey/journey_widget_test.dart` | 3 failures as intended (2.5 km, 800 m, and lookup/text agreement at 20 m); the default 1.5 km case passes. File restored before commit |
| 2026-10-02 | M3 review cleanup | `dart format --set-exit-if-changed .`; `flutter analyze`; `flutter test` | Pass: exit 0 (81 files, 0 changed); no issues; **255/255** (247 + 8 new: 1 busrouter invalid-share boundary, 2 distance text, 4 MRT "none within" text, 1 held bus-data failure) |
| 2026-10-02 | M3 review cleanup | `flutter test integration_test -d emulator-5554` | Pass, 5/5 (the journey card is rendered in the happy and fallback paths) |
| 2026-10-02 | M3 review cleanup | `flutter build web`; `flutter build apk --debug` | Pass; pass |
| 2026-10-02 | M4 feasibility: ArriveLah (curl) | `curl -D - 'https://arrivelah2.busrouter.sg/?id=03019'` with `Origin: http://localhost:8080`, plus an OPTIONS preflight; edge cases `?id=99999`, `?id=abc`, no id; stops 75009, 46239, 14141 (03:01–03:02 UTC) | HTTP 200, 160 ms, `application/json`, `Access-Control-Allow-Origin: *`, `Access-Control-Allow-Headers: *`, `Cache-Control: max-age=15`, no auth. Schema as in `data-sources.md` § ArriveLah. `99999` → `{"services":[]}`; `abc` → HTTP 200 `{"error":"Failed to retrieve bus data.","statusCode":500}`; no id → instruction object. 141 buses sampled: 76 `monitored` 1, 65 `monitored` 0 (lat/lng 0); `visit_number` 2 seen 4 times (loop 291/293 at 75009). `subsequent` always equalled `next2` |
| 2026-10-02 | M4 feasibility: rate limit | 10 stops × (GET + HEAD) within ~3 s (03:02 UTC) | 20/20 HTTP 200, no rate-limit or `Retry-After` headers. No limit is published; none is assumed or coded |
| 2026-10-02 | M4 feasibility: real Chrome (CORS enforced) | A static page served by `python -m http.server` on `http://localhost:8765`, opened in Chrome 154, `fetch()` of `?id=03019`, `99999`, `abc` (03:03:39 UTC) | All three fetched and their JSON read by the page (03019: 10 services; 99999: empty list; abc: the error body). CORS allowed from a localhost origin |
| 2026-10-02 | M4 feasibility: source and licence | `gh api repos/cheeaun/arrivelah` and its `api/arrival.js` | Proxies LTA DataMall v3 BusArrival with server-side keys; null slot = no `EstimatedArrival`; errors returned as HTTP 200 + `error`; `duration_ms` computed at response time. **No licence file** (`license: null`). Last push 2026-09-13, not archived |
| 2026-10-02 | M4 parser tests | First run of `test/features/bus_arrival/arrivelah_parser_test.dart` | 1 failure, a **real bug**: `"2026-13-45T25:00:00+08:00"` parsed to 2027-02-14 17:00Z (`DateTime.parse` rolls fields over), a made-up ETA. Fixed: the parser requires an explicit offset and checks the parsed instant gives back the exact fields sent; more invalid cases added (Feb 30, minute 61, offset +25:00). Then pass |
| 2026-10-02 | M4 state tests | First run of `test/features/bus_arrival/journey_arrivals_test.dart` | 2 failures, a test bug: they expected 1 plan build, but the overridden plan provider builds once with no plan and once when the test sets it. Changed to assert the count does not grow on refresh/Retry. Then 9/9 |
| 2026-10-02 | M4 widget tests | First run of `test/features/bus_arrival/arrivals_widget_test.dart` | 2 failures, test bugs: (1) `textContaining('Arr')` also matched "Arrivals: ArriveLah"; (2) the journey card is one merged semantics node, so the spoken ETA is checked inside the card's label. While fixing (1), an edit script turned `\b` into backspace characters, which made that check vacuous; caught by inspecting the line, fixed to `RegExp(r'\bArr\b')`. Then pass |
| 2026-10-02 | M4 mutation check | `option_arrivals.dart` temporarily without the plan-identity guard, then `flutter test test/features/bus_arrival/arrivals_widget_test.dart` | 1 failure as intended ("a loaded journey's arrivals are not shown on the next journey while its own are loading, even for the same stop"). File restored before commit |
| 2026-10-02 | M4 | `flutter test` (before the device runs) | Pass, 319/319 (255 from M1–M3, all still passing, + 64 new: 22 parser, 10 domain, 13 repository/cache, 9 state, 10 widget. Two M3 journey widget tests were adapted, none removed: the "not available yet" text is replaced by the arrivals footer) |
| 2026-10-02 | M4 | `flutter test integration_test -d emulator-5554` (Pixel 8 Pro cold-booted with `-no-snapshot-load`) | Pass, 5/5. Happy path now ends with live ETA → manual refresh after the TTL → new ETAs; fallback path adds direct bus → arrival `NetworkUnavailable` (route kept, Retry) → recovery → ETA |
| 2026-10-02 | M4 on-device smoke (§18 item 8, live ETA) | Release APK (`flutter build apk --release`, 48.7 MB) on emulator-5554, `adb emu geo fix 103.8514 1.2840` (Raffles Place), real geolocator, live busrouter / OneMap / ArriveLah. Destination VIVOCITY (098585) | Same M3 route (03019 OUE Bayfront → 14141, Bus 10 suggested; 57 and 100 alternatives). App checked at **11:31 SGT** (≈ 03:31:21Z): Bus 10 "Arr · 24 min · 32 min", 57 "7 · 17 · 36 min", 100 "10 · 18 · 25 min", next-bus details "Seats available · Wheelchair accessible · Double/Single deck". **Raw** `?id=03019` at 03:31:28Z (Vercel HIT, age 3 s): 10 → 11:31:00 / 11:55:47 / 12:03:38, 57 → 11:38:35 / 11:49:09 / 12:08:12, 100 → 11:41:25 / 11:49:32 / 11:56:52; loads SEA, all WAB, 10 DD, 57/100 SD. Every label matches floor((time − 03:31:21Z) / 1 min) with ≤ 60 s → Arr |
| 2026-10-02 | M4 on-device smoke: manual refresh | Same session; waited ~70 s (past the 15 s TTL), tapped "Refresh arrivals" at 03:32:59Z; raw fetched at 03:33:04Z | Footer "checked 11:33 SGT". App: 10 "22 · 30 min" (the earlier "Arr" bus had passed and dropped out), 57 "5 · 16 · 35 min", 100 "8 · 16 · 24 min". Raw: 10 → 11:55:41 / 12:03:15, 57 → 11:38:50 / 11:49:39 / 12:08:15, 100 → 11:41:17 / 11:49:27 / 11:57:19: all match. A refresh inside the TTL making no request is covered by automated tests only (no request counter on the device) |
| 2026-10-02 | M4 on-device smoke: missing live arrival | GPS moved to stop 27461 (`geo fix 103.70505 1.35323`), app relaunched; destination MARINA BAY FINANCIAL CENTRE (TOWER 1) (018981) at 11:34 SGT | Planner: only Bus 651 connects (27461 Opp Blk 276B → 03391 Marina Bay Financial Ctr, 14 stops; raw busrouter check: 651 is the only service at 400 m). App: "No live arrival available" under Bus 651; route, walks and MRT shown; no "0 min". Raw `?id=27461` and `?id=27451` at 03:34:52Z list only 181 and 185: 651 is a peak-hour City Direct service, absent off-peak |
| 2026-10-02 | M4 on-device smoke (§18 item 10, provider offline) | Raffles Place → VivoCity loaded online (03:35:44Z), then `adb shell svc wifi disable` + `svc data disable` (ping 8.8.8.8 failed), waited 15 s, "Refresh arrivals" at 03:36:19Z; then network re-enabled and Retry at 03:36:51Z | Offline: each of the three options showed "Live arrivals: Network unavailable. Check your connection and retry." + Retry; walks, services, stops and MRT stayed; no ETA shown. After Retry: 10 "18 · 25 min", 57 "2 · 12 · 31 min", 100 "5 · 13 · 21 min"; raw at 03:36:5xZ: 10 → 11:55:51 / 12:02:44, 57 → 11:39:36 / 11:49:23 / 12:08:04, 100 → 11:42:34 / 11:50:19 / 11:57:57: all match. Emulator network restored |
| 2026-10-02 | M4 Chrome attempt (release web build, not a full smoke) | `flutter build web`, served on `http://localhost:8766`, opened in Chrome 154 | The app stayed on "Checking location permission…" while Chrome's own location prompt (browser UI, outside the page) was unanswered; Escape did not dismiss it, and the permission was not granted by the agent. No manual origin is offered in that state, so no journey could be planned in Chrome. **Observation for smoke item 1 (still open)**, not fixed in M4. ArriveLah CORS from a real Chrome page was verified separately (row above) |
| 2026-10-02 | M4 final gates @ 77c1c54 | `dart format --set-exit-if-changed .`; `flutter analyze`; `flutter test`; `flutter test integration_test -d emulator-5554`; `flutter build web`; `flutter build apk --release` | Pass: exit 0 (94 files, 0 changed); no issues; 319/319; 5/5; built; built (48.7 MB). The commit that adds this row changes only this file |
| 2026-10-02 | PR #8 follow-up: strict NEA timestamps | `parseSourceTimestamp` made strict and shared by NEA and ArriveLah; then `flutter test test/core/sgt_format_test.dart test/features/environment/nea_parsers_test.dart` | Pass, 50/50. Every pre-existing NEA, ArriveLah and core test still passed unchanged (140/140 across those suites), so valid timestamps parse as before |
| 2026-10-02 | PR #8 follow-up: mutation check | `sgt_format.dart` temporarily back to plain `DateTime.parse(value).toUtc()`, then the timestamp, NEA parser and ArriveLah parser tests | 28 failures as intended (rolled-over dates, missing/invalid offsets, NEA fixtures with a corrupted timestamp). File restored before commit. (A first attempt did not apply because of CRLF line endings; the run that followed it was against the real code and is not counted) |
| 2026-10-02 | PR #8 follow-up gates @ 2dd9849 | `dart format --set-exit-if-changed .`; `flutter analyze`; `flutter test`; `flutter test integration_test -d emulator-5554` (Pixel 8 Pro cold-booted with `-no-snapshot-load`); `flutter build web`; `flutter build apk --release` | Pass: exit 0 (94 files, 0 changed); no issues; **349/349** (319 + 30 new timestamp regression tests); 5/5; built; built (48.7 MB). The commit that adds this row changes only this file. Still open as documented: the Web/ChromeDriver integration run and smoke items 1, 3 and 5 |
| 2026-10-02 | M4 gate: `flutter build apk --debug` (missing from the M4 gate rows above) | `flutter build apk --debug` at 05:00:58Z on f66677a plus this cleanup's uncommitted comment/doc edits, i.e. the same code as the final cleanup commit (a first run at 04:59:15Z also passed, but the comment edit landed during it, so it is not counted) | Pass: `assembleDebug` 28.0 s, `Built build/app/outputs/flutter-apk/app-debug.apk`, exit 0. No other build or device run was done for this cleanup |
| 2026-10-02 | M4 cleanup: loop-terminal doc wording (comment and `assumptions.md` only; no code change) | `dart format --set-exit-if-changed .`; `flutter analyze`; `flutter test test/features/bus_arrival` | Pass: exit 0 (94 files, 0 changed); no issues; 64/64. The full `flutter test` suite, integration tests and other builds were not re-run for this comment-only change (last full run: the follow-up gates row above, 349/349 and 5/5) |
| 2026-10-02 | Issues #9–#18 (branch `fix/review-issues-9-18`): mutation check for #11 | `ref.watch(uiTickProvider)` temporarily removed from `environment_dashboard.dart`, then `flutter test test/widget_test.dart --plain-name "ages, the Stale marker"` | Fails as expected (`+0 -1`); file restored |
| 2026-10-02 | Issues #9–#18: release signing (#14) | `flutter build apk --release` with no key → built, and the `-v` log shows "WARNING: no release signing configured … signed with the DEBUG key". With a throwaway keystore (scratchpad, `CN=Throwaway Test`) via `android/key.properties`, and separately via `-PreleaseStoreFile=… -PreleaseStorePassword=… -PreleaseKeyAlias=… -PreleaseKeyPassword=…` → `apksigner verify --print-certs` shows `CN=Throwaway Test` both times. `key.properties` without `keyPassword` → `FAILURE … Release signing is partly configured; missing: [keyPassword]`. `flutter build apk --debug -v` → no warning. `ORG_GRADLE_PROJECT_*` variables did **not** reach Gradle through `flutter build` (the debug-key warning printed), so the docs use `-P`. The temporary `key.properties` was removed | Pass (as described) |
| 2026-10-02 | Issues #9–#18 gates @ 321bc43 | `dart format --set-exit-if-changed .`; `flutter analyze`; `flutter test`; `flutter build web`; `flutter build apk --debug`; `flutter test integration_test -d emulator-5554` (Pixel 8 Pro, cold boot) | Pass: 0 files changed; no issues; 389/389; web built; debug APK built; integration 5/5. **Not run:** Web/ChromeDriver integration (chromedriver not installed); live Chrome smoke of item 1; live device checks of the new UI (Keep this origin, Try location again, ETA countdown) |
| 2026-10-02 | PR #19 after merging `main` into `fix/review-issues-9-18` @ 85d46d1 (recorded late, in the PR #19 follow-up) | `dart format --set-exit-if-changed .`; `flutter analyze`; `flutter test` | Pass: 0 files changed; no issues; 389/389. **Not re-run after that merge:** `flutter build web`, `flutter build apk --debug` and `flutter test integration_test` (the merge brought only docs and comment changes from `main`; those gates last ran at 321bc43, row above) |
| 2026-10-02 | PR #19 follow-up (branch `fix/pr19-followups`): late denial after the permission timeout | New tests in `test/features/origin/origin_controller_test.dart`, "background retry with a manual origin": manual origin → Try location again → 10 s permission timeout → late `denied` / `deniedForever` / `serviceDisabled`, a throwing permission request, and a superseded attempt answering late. `flutter test test/features/origin/origin_controller_test.dart --plain-name "permission timeout, then a late"` | Pass (3/3). Mutation check: with `origin_controller.dart` from `origin/main` (b573af7), the file gives `+41 -4` (the three late-outcome tests and the throwing-request test fail; the superseded-attempt test passes on both, as it guards an existing protection); with the fix, 45/45 |
| 2026-10-02 | PR #19 follow-up: partial signing config | Temporary gitignored `android/key.properties` with `storeFile`, `storePassword`, `keyAlias` but no `keyPassword`, then `flutter build apk --debug` | `FAILURE: Build failed with an exception.` / `Release signing is partly configured; missing: [keyPassword]`: a **debug** build fails too, as now documented in `docs/release-signing.md`. Temporary file removed |
| 2026-10-02 | PR #19 follow-up gates @ f19cc6e | `dart format --set-exit-if-changed .`; `flutter analyze`; `flutter test`; `flutter build web`; `flutter build apk --debug`; `flutter test integration_test -d emulator-5554` (Pixel 8 Pro, cold boot) | Pass: 0 files changed (exit 0); no issues; 394/394; web built; debug APK built; integration 5/5. **Not run:** release APK build (signing code unchanged); Web/ChromeDriver integration (chromedriver not installed); a live device check of the late-denial note |
| 2026-10-02 | App-bar icon (branch `feat/app-bar-icon`) | `dart format --set-exit-if-changed .`; `flutter analyze`; `flutter test` (incl. new `test/app/app_logo_test.dart`); `flutter build web`; `flutter build apk --debug`; then `flutter run -d web-server --web-port 8766` opened in Chrome 154 | Pass: 0 files changed; no issues; 397/397; web built; debug APK built. In Chrome the mark shows left of "Singapore Smart Commute" in the app bar, sized and centred to the title. **Not run:** Android integration tests and an on-device look (only the app bar changed; the existing boot tests still find the title) |
| 2026-10-02 | App-bar icon switched to the user's PNG (branch `feat/app-bar-icon`) | Source 1254×1254 RGB PNG cropped to its rounded tile (box 126–1128), corners made transparent with a fitted superellipse mask (n = 5), saved as `assets/app_icon.png` (192×192 RGBA, 61 KB); previews checked at 28/56/160 px on the app-bar colour and on white (no white box or halo). Then `dart format --set-exit-if-changed .`; `flutter analyze`; `flutter test`; `flutter build web`; `flutter build apk --debug`; `flutter run -d web-server --web-port 8766` in Chrome 154 | Pass: 0 files changed; no issues; 398/398; web built; debug APK built. In Chrome the icon shows at 32 px left of the title with clean rounded corners. **Not run:** Android integration tests and an on-device look |
| 2026-10-02 | Responsive Conditions grid (branch `feat/compact-dashboard-grid`) | `dart format --set-exit-if-changed .`; `flutter analyze`; `flutter test` (incl. new `test/features/environment/conditions_grid_test.dart`); `flutter build web`; `flutter build apk --debug`; `flutter test integration_test -d emulator-5554` (Pixel 8 Pro, cold boot) | Pass: 0 files changed; no issues; 404/404; web built; debug APK built; integration 5/5. Mutation check: with `BusyRow` from `origin/main` (no `Flexible`), the "loading and waiting-for-location states fit a 2 × 2 tile" test reports RenderFlex overflows of 126–198 px; with the fix it passes |
| 2026-10-02 | Responsive Conditions grid, live look in Chrome 154 | `flutter run -d web-server --web-port 8766`, live data.gov.sg + OneMap, origin Raffles Place MRT. Full window (~1500 px): four tiles across, equal height, Conditions wider than the 640 px cards. Phone width: the app in a 400 × 860 iframe: 2 × 2 grid (forecast + UV, PM2.5 + PSI), each tile with value/category, scope and "As of … · N min ago", no overflow | Pass. **Not checked live:** the one-column fallback (narrow / large text) and the Stale / error / Retry states in the grid — covered only by the widget tests with fakes; not looked at on a physical phone |
| 2026-10-02 | Responsive Conditions grid: final Android integration run at PR head `cc84345` | Clean tree at `cc84345` (no uncommitted changes). Pixel 8 Pro AVD cold-booted (`-no-snapshot-load`), then one uninterrupted `flutter test integration_test -d emulator-5554` (10:05-10:13 UTC); emulator boot id `5f3595fc-70ed-4528-8d02-36f4ae6f9f70` read before and after the run, unchanged | Pass: exit 0, 5/5 in a single run (`app_boot_test`, `fallback_path_test`, `happy_path_test`), no failures. The earlier 5/5 above was on the same functional tree before the docs-only edit; this row is the run at the final head |
| 2026-10-02 | PR #21 + #22 merge verification (merge commit `18a0766` on `feat/compact-dashboard-grid`; its tree is identical to `main` at `b3ede14`, checked with `git diff --quiet 18a0766 b3ede14`) | After resolving the `docs/testing.md` run-log conflict (both sides kept): `dart format --set-exit-if-changed .`; `flutter analyze`; `flutter test` | Pass: 99 files, 0 changed; no issues; 408/408. `pubspec.lock` unchanged by `flutter pub get`. The merged tree equals `main` plus exactly PR #22's diff. **Not run on the merge:** Android/Web integration and builds (the Android 5/5 is the run at `cc84345` above; the two PRs were tested independently) |
