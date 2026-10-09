# E2 Static Estimated Journey Time: Implementation Plan

**Status:** approved in principle. Q1–Q10 frozen by the owner on 2026-10-09 (§2). This document is a plan: no
production code, test, dependency or build configuration changes in the PR that adds it.

**Baseline:** `main` = `origin/main` = `f9863553e43a0d78d854dbb6d5a007b11147347e` (`f986355`, merge of PR #75),
verified after `git fetch --prune origin` on 2026-10-09.

**What E2 is.** A post-submission enhancement, outside the milestones, like E1, E3 and E4. Each **direct-bus option**
gets a static estimate of the trip:

```text
existing access walk + estimated bus ride + existing egress walk,  rounded up to the next 5 minutes
```

The estimate is display-only. It excludes waiting and live traffic, and it never changes the plan.

**Sources:**
- the E2 discovery report (2026-10-06) and its calibration scripts;
- the Phase B E5/E6 feasibility studies (2026-10-09);
- the code at the baseline.

The discovery and verification scripts are kept outside the repository and are not committed (ruling Q10). Their
results are quoted here.

---

## 1. Current-code findings (`f986355`)

**Planner.** `lib/features/journey/domain/direct_bus_planner.dart`:
- `BusOption` holds `service`, `direction`, `board`, `boardIndex` (the ride's occurrence in the direction's list),
  `alight`, `stops`, `walkToStop`, `walkFromStop`, `score`, `towardName` and `isLoop`.
- `stops = index(alight) − index(board)`, where the alighting index is the first occurrence after the boarding one
  (`_option(..., i, j - i, ...)`).
- `score = walkTo.minutes + walkFrom.minutes + 1.5 × stops`.
- **E2 does not touch this file.**

**Walks.** `lib/features/journey/domain/walking.dart`:
- `WalkEstimate.minutes = ceil(haversine × 1.3 / 80)`; its label is `~N min walk (est.)`.
- These integers are "the displayed walking durations" E2 reuses.
- With the 800 m maximum radius a walk is 0–13 min. All of 0–13 were seen in a 2,453-option real-data sample.

**Distance.** `lib/core/geo/geo.dart`: `haversineMeters` uses `_earthRadiusMeters = 6371000`.

**Network.**
- `BusNetwork { stops: Map<String, BusStop>, services: Map<String, BusService> }` is held for the session by
  `busNetworkProvider` (`lib/features/journey/journey_providers.dart`).
- `journeyPlanProvider` awaits it only when the trip is not walk-only. A displayed `DirectBusOptions` therefore
  implies a settled network.
- `mapSceneProvider` (`lib/features/map/map_providers.dart`) reads `busNetworkProvider` only when the plan is a
  `DirectBusOptions`. E2 uses the same pattern, so a walk-only journey never loads bus data.

**Journey card.** `lib/features/journey/presentation/journey_card.dart`:
- `JourneyCard` watches the plan, the MRT suggestion and the option selection.
- `_Option` builds a summary column: the "Take Bus N toward X" title (`titleSmall`, a `FocusLanding`), then
  `OptionArrivals`.
- `_Steps` builds walk, "N stops", "Alight at …", walk. Alternatives show only the first walk until "Show steps".
- The card ends with `Text(JourneyCard.estimateNote)`: "Walking times are straight-line estimates, not routes."

**Untouched by E2.**
- Arrivals: `journeyArrivalsProvider` (`lib/features/bus_arrival/bus_arrival_providers.dart`).
- Map: `routes.min.json` is reachable only through `routeGeometryProvider`, watched only by the open map.
- `features/journey` never imports `features/map`.

**Config.** `JourneyConfig` in `lib/core/config/app_config.dart` holds the planner tunables. The E2 constants go
there.

**Tests and harness.**
- `test/features/journey/*_test.dart` and `test/features/bus_arrival/arrivals_widget_test.dart`.
- Fakes in `integration_test/fakes/`:
  - `fake_bus_network.dart`: F10, F20 and F30 between Bishan and VivoCity.
  - `buildTestApp` takes `busNetwork`, `busArrivals` (the fake counts `calls` per stop) and `routeGeometry` (the fake
    counts `loads`).
- `integration_test/happy_path_test.dart` runs on Android and Web.

**CI.**
- `.github/workflows/flutter-test.yml` runs format, analyze and `flutter test` on every push. Its Linux Chrome step
  runs `flutter test --platform chrome test/features/map/polyline_codec_test.dart`.
- Windows Smart App Control blocks `flutter_tester.exe` on the development PC, so `flutter test` evidence comes from
  CI. The Windows Chrome runner is known broken (`docs/testing.md`) and is not retried.

**A rule E2 supersedes.** The `docs/assumptions.md` row "Journey options" says *"No total journey time is shown: there
is no in-vehicle time, so a total would be invented"*. E2 amends it (§12).

## 2. Frozen decisions (owner rulings, 2026-10-09)

| # | Ruling |
|---|---|
| Model | Bus minutes = `2.85 × km + 0.35 × stops`. `stops` = traversed stop segments = `alightIndex − boardIndex`. `km` = sum of the straight-line distances between consecutive stops of the ride, with the existing 6,371,000 m Earth radius. The explicit occurrence indices are kept for loops and repeated stops |
| Walks | The existing displayed integer walking minutes (`walkToStop.minutes`, `walkFromStop.minutes`), unchanged |
| Q1, ride rounding | The ride detail is rounded **up** to a whole minute |
| Total rounding | Rounded **up** to the next 5 minutes, in the exact order of §3.2 |
| Exclusions | No live waiting, live traffic, vehicle position, clock time or rush-hour uplift |
| Invariants | No change to planner ranking, scores, option order, Suggested, candidate stops, arrivals, selection or the map |
| Q9, scope | Direct-bus options only: Suggested and **every alternative, including collapsed ones**. Walk-only and the MRT suggestions are unchanged. No E2 total on E5 transfer journeys |
| Q2/Q3, trip line | Below the live arrivals: `About N min · excl. waiting`; spoken `Estimated trip, about N minutes, not including waiting` |
| Q3, ride step | In the expanded steps: `N stops · ~M min ride (est.)`; spoken `N stops, about M minutes on the bus, estimated` |
| Q8, walk steps | The walking steps' text and semantics stay unchanged |
| Footer | One E2 footer: `Trip times are rough estimates based on scheduled early/late bus timings. They exclude waiting and live traffic conditions.` No claim of typical, daytime or rush-hour accuracy anywhere |
| Q4, validity | 300-minute guard on the bus estimate. An invalid, non-finite, negative or over-300 estimate is **omitted, never clamped**. The journey stays available |
| Q5, docs | Amend `docs/assumptions.md` "Journey options", and record the calibration provenance honestly (§12) |
| Q6, process | This docs-only plan PR first. It is not merged by the agent, and the implementation branch is not created yet |
| Q7, CI | Add the pure estimator test to the existing Linux Chrome CI step, in the implementation PR |
| Q10, scripts | Calibration and verification scripts are not committed. The provenance goes in the docs |
| Architecture | A small pure estimator in the journey domain, reusable per bus leg (E5). No map import, no `routes.min.json`, no runtime dataset, API, host, backend, secret or dependency. No provider, planner, arrivals or map architecture change |

**Footer interpretation (for confirmation in review).** "One footer" is read as follows:
- E2 adds exactly one explanatory line, with the frozen text.
- That line is shown only when at least one displayed option has an estimate.
- The existing walking note `JourneyCard.estimateNote` predates E2 and stays unchanged. Its test also stays unchanged.

If the ruling means the walking note should be replaced, that is a change to an existing test and needs an explicit
ruling before T2.

## 3. Exact mathematical specification

### 3.1 Bus leg

The inputs are the session `BusNetwork network` and one bus leg: `service`, `direction`, `boardIndex` and `stopCount`.
For a direct option these are `option.service`, `option.direction`, `option.boardIndex` and `option.stops`.

```text
codes = service.directions[direction]          // the app's parsed list; planner indices
i = boardIndex
n = stopCount                                  // traversed segments = alightIndex − boardIndex

leg is valid only if:
  n ≥ 1, i ≥ 0, i + n ≤ codes.length − 1
  every codes[k] for k in [i, i+n] is a key of network.stops
  (direct option) codes[i] == option.board.code and codes[i+n] == option.alight.code

meters   = Σ_{k=i}^{i+n−1} haversineMeters(position(codes[k]), position(codes[k+1]))   // R = 6,371,000 m
km       = meters / 1000
busExact = 2.85 × km + 0.35 × n                // minutes (double)

estimate is valid only if busExact is finite and 0 ≤ busExact ≤ 300
otherwise: no estimate (never clamped to 300)
```

- **Only the ride's own sublist from `boardIndex` is summed.** The planner's occurrence is used, never the head of the
  route and never the straight board → alight line.
- **Loops and repeated stops are handled by the indices alone.** On a loop such as `L0 L1 L2 L1 L3 L0`, boarding L1 at
  index 3 gives one segment. Index 1 would give three.

### 3.2 Rounding order (frozen)

```text
1. busExact              (double, §3.1)
2. busShown  = ceil(busExact)                         // integer; ≥ 1 because n ≥ 1 ⇒ busExact ≥ 0.35
3. total     = walkTo + busShown + walkFrom           // integers: walkTo = option.walkToStop.minutes,
                                                      //           walkFrom = option.walkFromStop.minutes
4. shown     = (total + 4) ~/ 5 × 5                   // integer arithmetic only: smallest multiple of 5 ≥ total
display: trip line "About {shown} min · excl. waiting"; ride step "~{busShown} min ride (est.)"
```

**Rule:** the displayed total is the smallest multiple of 5 that is ≥ the sum of the displayed parts (walk to stop +
ride + walk from stop). So `parts ≤ shown < parts + 5`, and `shown` is always a multiple of 5.

### 3.3 Threshold evidence (measured 2026-10-09, before freezing)

Every case was checked two ways. One is the frozen order above. The other rounds the exact sum
`walkTo + busExact + walkFrom` up to 5, in double arithmetic.

- **Real options:** every displayed direct option in a 2,526-query real-data sample on the live busrouter data,
  2,453 options in all, with walks of 0–13 min. Results:
  - 0 disagreements between the two methods;
  - 0 cases where the displayed total breaks the rule above.
- **Sweep:** every walk pair 0–13 × 0–13, and rides `k + d` for k = 1…300 and
  d ∈ {−10⁻⁹, 0, 10⁻⁹, 0.01, 0.49, 0.5, 0.51, 0.99}. That is 470,400 cases: 0 disagreements and 0 rule violations.
- **Why not round-to-nearest for the ride.** It would disagree with the exact sum in 246 of the 2,453 real options
  and 35,280 sweep cases. For example, walks 0 + 0 with a ride of 5.000000001 shows 5, where the exact sum gives 10.
  The ceiling order agrees because each multiple of 5 is an integer, so rounding `x` up to 5 equals rounding `ceil(x)`
  up to 5. The walks are already integers.
- **Named threshold cases** (to become tests, T1):

| Walk to | Ride (exact) | Walk from | Ride shown | Parts | Shown |
|---|---|---|---|---|---|
| 2 | 22.0 | 1 | 22 | 25 | **25** |
| 2 | 22.0000001 | 1 | 23 | 26 | **30** |
| 2 | 21.9999999 | 1 | 22 | 25 | **25** |
| 2 | 21.5 | 1 | 22 | 25 | **25** |
| 3 | 20.0 | 2 | 20 | 25 | **25** |
| 3 | 20.01 | 2 | 21 | 26 | **30** |
| 1 | 27.6 | 1 | 28 | 30 | **30** |
| 1 | 28.01 | 1 | 29 | 31 | **35** |
| 0 | 3.5190554 | 0 | 4 | 4 | **5** |
| 13 | 120.9 | 13 | 121 | 147 | **150** |
| 0 | 300.0 | 0 | 300 | 300 | **300** (at the guard: valid) |

### 3.4 Golden values (computed with the app's own `haversineMeters`)

| Fixture | n | km | busExact | busShown |
|---|---|---|---|---|
| Meridian: stop k at (1.30 + 0.01·k, 103.80); one hop = 1,111.9492664 m | 1 | 1.1119493 | 3.5190554 | 4 |
|  | 3 | 3.3358478 | 10.5571662 | 11 |
|  | 10 | 11.1194927 | 35.1905541 | 36 |
|  | 35 | 38.9182243 | 123.1669393 | 124 |
|  | 85 | 94.5157 | ≈ 299.1 | 300 (valid) |
|  | 86 | 95.6276 | ≈ 302.6 | **no estimate** (over the guard; not 300) |
| Meridian, 3 stops from index 5 | 3 | 3.3358478 | 10.5571662 | 11 |
| U-shape (1.30,103.80) → (1.31,103.80) → (1.31,103.81) → (1.30,103.81) | 3 | 3.3355572 (straight end to end 1.1116631) | 10.5563379 (straight line would give 4.2182) | 11 |
| Loop `L0 L1 L2 L1 L3 L0` at (1.30,103.80), (1.31,103.80), (1.32,103.80), L1, (1.31,103.81), L0: board index 3 → L3 | 1 | 1.1116586 | 3.5182271 | 4 |
|  wrong occurrence, index 1 → L3 | 3 | 3.3355572 | 10.5563379 | (mutation value) |

App fakes, GPS Bishan (1.3508, 103.8485) → VivoCity (1.2643, 103.8223):

| Option | km | busExact | Ride | Walks | Parts | Shown |
|---|---|---|---|---|---|---|
| F20 BSH2 → VIV1, 2 stops (Suggested) | 10.5502 | 30.7680 | 31 | 2 + 1 | 34 | **35** |
| F10 BSH1 → VIV1, 3 stops | 10.7265 | 31.6205 | 32 | 1 + 1 | 34 | **35** |
| F30 BSH1 → VIV1, 3 stops | 10.1522 | 29.9838 | 30 | 1 + 1 | 32 | **35** |

**Real-data range.** The longest full direction is 858 direction 0: 74 stops, 66.7 km, 216.1 min. Over every
displayed direct option in the sample: ride p50 18 min, p95 70, max 120.9; shown total p50 30, p95 90, max 145. The
300-minute guard sits above all real data.

### 3.5 Calibration provenance (what the constants rest on)

- **Data:**
  - LTA DataMall BusRoutes scheduled arrival times of the **first and last bus** of the day at every stop
    (`WD_FirstBus`, `WD_LastBus`), under the Singapore Open Data Licence.
  - Read once offline, on 2026-10-06, through busrouter's keyless copy `data.busrouter.sg/v1/raw/bus-routes.datamall.json`.
  - The app never loads it, and no key was used.
- **Direction coverage is incomplete.** Only directions whose busrouter stop list equals DataMall's, and whose times
  are complete and monotonic, were usable: **462** weekday-first-trip and **730** weekday-last-trip directions of the
  798.
- **Rides:**
  - **11,914** sampled rides on those directions: 10 random segments per direction and schedule, the alighting stop
    at its first occurrence after boarding.
  - Split by service into 5,870 fit and 6,044 held-out test rides.
  - 2,714 rides lie on loop directions. 133 (1.1 %) are whole loops, which the planner never produces.
- **Fit:** pooled least-absolute-error, giving 2.85 min per straight-line km + 21 s (0.35 min) per traversed segment.
  The stop and distance definitions are the ones in §3.1.
- **Error on the 6,044 held-out rides:**
  - median absolute error **3.4 min**, 90th percentile **12.9 min**;
  - relative (rides ≥ 10 min) median 18.9 %, 90th percentile 40.6 %;
  - the model is below the schedule in 63 % of rides.
- **Limitations:**
  - **off-peak only** (first and last trips run early morning and late night); there is no daytime or rush-hour
    evidence;
  - the coefficients are collinear, so the split between km and stops is not stable, though the predictions are;
  - express and City Direct services have larger errors.
  - **Extrapolation:** the model is applied to every direction, including the ones excluded from calibration.
- **Reproduction (2026-10-09):**
  - re-running the calibration code gives the same 11,914 rides and the same test errors;
  - the app's own parser and `haversineMeters`, applying §3.1, reproduce every ride's km to 5.7 × 10⁻¹² km and its
    minutes to 1.6 × 10⁻¹¹;
  - the inputs were byte-identical busrouter files;
  - `0.35 == 21/60` in doubles.

## 4. Domain architecture

One new pure-Dart file, `lib/features/journey/domain/journey_estimate.dart`. It imports only
`../../../core/config/app_config.dart`, `../../../core/geo/geo.dart`, `bus_network.dart` and `direct_bus_planner.dart`
(for `BusOption`). It has no Flutter, Riverpod, HTTP, bus-arrival or map import.

```dart
/// E2 static in-bus estimate for one ride (docs/assumptions.md "Estimated
/// trip time (E2)"): straight-line km between consecutive stops of the ride
/// × [minutesPerKm] + [minutesPerStop] × traversed segments. Unrounded
/// minutes; null when the leg is invalid or the result is non-finite,
/// negative or over [JourneyConfig.busEstimateMaxMinutes] (never clamped).
double? estimateBusMinutes(
  BusNetwork network, {
  required BusService service,
  required int direction,
  required int boardIndex,
  required int stopCount,
  double minutesPerKm = JourneyConfig.busMinutesPerKm,     // test seam only
  double minutesPerStop = JourneyConfig.busMinutesPerStop, // test seam only
});

/// One direct option's estimate, in the frozen rounding order (§3.2).
class DirectJourneyEstimate {
  const DirectJourneyEstimate({
    required this.walkToStopMinutes,
    required this.rideMinutes,
    required this.walkFromStopMinutes,
  });
  final int walkToStopMinutes;   // option.walkToStop.minutes
  final int rideMinutes;         // ceil(estimateBusMinutes(...))
  final int walkFromStopMinutes; // option.walkFromStop.minutes
  int get partsMinutes => walkToStopMinutes + rideMinutes + walkFromStopMinutes;
  int get shownMinutes =>
      roundUpToMultiple(partsMinutes, JourneyConfig.estimateRoundingMinutes);
}

/// Null when the ride cannot be estimated, or its board/alight codes don't
/// match the network at those indices.
DirectJourneyEstimate? estimateDirectJourney(BusOption option, BusNetwork network);

/// Smallest multiple of [step] ≥ [minutes]; integer arithmetic.
int roundUpToMultiple(int minutes, int step) => (minutes + step - 1) ~/ step * step;
```

**Constants** in `JourneyConfig`, documented with their evidence:
- `busMinutesPerKm = 2.85`;
- `busMinutesPerStop = 0.35`;
- `estimateRoundingMinutes = 5`;
- `busEstimateMaxMinutes = 300`.

**Leg-level by design.** `estimateBusMinutes` takes exactly the fields of a future E5 `BusLeg` (service, direction,
boardIndex, stopCount). E2 adds no leg type, rail type or multimodal framework.

**Where it runs.** In `JourneyCard.build`, only for a settled `DirectBusOptions`:
- read `ref.watch(busNetworkProvider).value`, the `mapSceneProvider` pattern, so walk-only never loads bus data;
- compute `[for (o in plan.options) estimateDirectJourney(o, network)]` and pass it down to `_Plan`, `_Option` and
  `_Steps`;
- if the network value is null, every estimate is null.

The cost is at most 3 options × 104 haversines, a few microseconds. **No new provider:** a pure function of the
displayed plan's own options cannot attach to another plan.

**Not touched:** `direct_bus_planner.dart`, `journey_providers.dart`, `features/bus_arrival/**`, `features/map/**`, the
fakes, the CSP, `pubspec.yaml` and `pubspec.lock`.

## 5. Proposed file changes (implementation PR, not this plan PR)

| File | Change |
|---|---|
| `lib/core/config/app_config.dart` | `JourneyConfig` gains the 4 constants (§4), with doc comments pointing to `docs/assumptions.md` |
| `lib/features/journey/domain/journey_estimate.dart` | **New** (§4) |
| `lib/features/journey/presentation/journey_card.dart` | Compute the estimates. Add the trip line under `OptionArrivals` in each `_Option`, and the ride detail on the bus step in `_Steps`. Add `JourneyCard.tripEstimateNote` (the frozen footer). Add static string helpers for tests: `tripLine(int)`, `tripSemantics(int)`, `rideStep(int stops, int minutes)`, `rideSemantics(int stops, int minutes)` |
| `test/features/journey/journey_estimate_test.dart` | **New**, pure Dart: imports only `package:flutter_test/flutter_test.dart` (for `test`/`expect`) and `lib/` domain files, with no widgets and nothing from `integration_test/`, like `polyline_codec_test.dart`, so it also runs on Chrome |
| `test/features/journey/journey_widget_test.dart` | New group "estimated trip time (E2)" (§8 T2). Existing tests unchanged |
| `test/features/journey/journey_estimate_invariants_test.dart` | **New**: ranking, arrivals, geometry, request and import guards (§8 T3) |
| `integration_test/happy_path_test.dart` | Assert the Suggested trip line and the footer, and their absence on walk-only |
| `.github/workflows/flutter-test.yml` | The Linux Chrome step also runs `test/features/journey/journey_estimate_test.dart` (ruling Q7) |
| `README.md`, `CLAUDE.md`, `docs/architecture.md`, `docs/assumptions.md`, `docs/data-sources.md`, `docs/testing.md` | §12 |

The bus step's singular stays as today: `1 stop · ~4 min ride (est.)`, spoken `1 stop, about 4 minutes on the bus,
estimated`.

## 6. UI layout

```text
Suggested
[ 88 ]  Take Bus 88 toward Toa Payoh Int          titleSmall            (unchanged)
        Next buses: Arr · 7 min · 15 min          OptionArrivals        (unchanged)
        About 15 min · excl. waiting              NEW: bodyMedium, colorScheme.onSurfaceVariant
[walk] ~1 min walk (est.) to Bus Stop 53231 — Bishan Stn                (unchanged)
[bus]  7 stops · ~11 min ride (est.)             bus step + NEW detail (expanded steps only)
[stop] Alight at 52501 — Bef Toa Payoh Pk                               (unchanged)
[walk] ~2 min walk (est.) to destination                                (unchanged)
[Selected] [Show steps]
Alternatives … each with its own trip line, also when collapsed; ride detail after "Show steps"
Refresh arrivals footer                                                  (unchanged)
────────────
MRT alternative …                                                        (unchanged, no estimate)
Walking times are straight-line estimates, not routes.                   (unchanged)
Trip times are rough estimates based on scheduled early/late bus timings. They exclude waiting and live traffic
conditions.                                                              NEW: bodySmall, only when ≥ 1 estimate
```

**Trip line**
- Placement: directly below `OptionArrivals`, in the summary column.
- Style: `bodyMedium`, coloured `onSurfaceVariant`. This is lighter than the arrivals, and it uses none of their words
  ("Next", "Arr", clock times). No icon: position, style and wording separate it.
- Semantics: `Text(..., semanticsLabel: tripSemantics(n))`. It is not a header, not a live region and not focusable.
  It is read after the arrivals and before the steps.
- It renders whatever the arrivals' state: loading, failed, outdated or refreshed. "Refresh arrivals" and the UI tick
  never change it.

**Ride step**
- `'$stops ${stops == 1 ? 'stop' : 'stops'} · ~$minutes min ride (est.)'`, with
  `semanticsLabel: '$stops ${stops == 1 ? 'stop' : 'stops'}, about $minutes minutes on the bus, estimated'`.
- Walk steps are unchanged.

**No estimate** for an option: that option has no trip line, and its bus step stays exactly `N stops` as today.

**Responsive.**
- Plain wrapping `Text` (no `FittedBox`, ellipsis or fixed height).
- At 360 dp and 320 dp with 2× text, the trip line wraps to two lines, with no overflow.

**Palettes.**
- Colours come only from `colorScheme`, so `test/app/app_theme_test.dart` stays green.
- The trip line's contrast against the Card colour must be ≥ 4.5:1 in all 5 palettes, in light and dark (T2.10).

## 7. Failure behaviour

**`estimateBusMinutes` returns null and never throws** when:
- `stopCount < 1`;
- `boardIndex < 0`, or `boardIndex + stopCount` is past the end of the direction;
- `direction` is out of range;
- a ride code is missing from `network.stops`;
- the result is non-finite (NaN or Infinity, e.g. from a non-finite coordinate), negative, or over 300 min.

**`estimateDirectJourney`** returns null for any of those, and when the board or alight code disagrees with the list at
those indices. That is the same plan/network check as `_rideOf` in `map_scene.dart`.

**What null changes.**
- **Changed for that option only:** no trip line, and the ride step has no detail.
- **Unchanged:** every other option, the option itself, Suggested, the order, arrivals, Select, Show steps, the map
  and the MRT section.
- No error text, placeholder, SnackBar, retry or runtime log. The footer is hidden if no displayed option has an
  estimate.

`routes.min.json` and its failures are irrelevant: the estimator never reads them.

## 8. Test-first task sequence

**Process** (as in the Phase A plan, §3.3):
- Commit the RED tests and push. Record the CI run and its intended failures.
- Commit the implementation and push. Record the GREEN `N/N`.
- Run each mutation on a throwaway `mut/e2-<id>` branch (§9), then delete it.
- `dart format` and `flutter analyze` run locally and in CI.
- `flutter test` runs in CI only (Smart App Control).

**T0 Baseline.**
- `git fetch --prune origin`; `main` must equal `origin/main`. Reconcile §1 if `main` moved, and stop if the journey,
  arrivals or map files changed.
- `git switch -c feat/e2-static-journey-time` from the latest `origin/main`, after this plan PR is merged.
- Record the CI baseline `N/N` on the branch's first push.

**T1 Estimator** (`journey_estimate_test.dart`, pure):
1. **Distance and stop count:** the meridian goldens for 1, 3, 10 and 35 stops (`closeTo(…, 1e-9)` on `busExact`,
   exact on `ceil`).
2. **Later boarding occurrence:** 3 stops from index 5 equal the golden, and differ from the same count summed from
   index 0 of a non-uniform fixture.
3. **Hop sum, not the straight line:** U-shape → 10.5563379.
4. **Loop and repeated stop:** `L0 L1 L2 L1 L3 L0` boarded at index 3 → L3 is 1 segment, 3.5182271.
5. **Coefficients:** two fixtures with different km/segment mixes equal `2.85·km + 0.35·n` exactly. This separates the
   terms.
6. **Alternatives differ:** the same stop pair on two services or directions gives distinct values.
7. **Validity:**
   - each structural case in §7 returns null;
   - NaN coordinates in a stop → null (non-finite);
   - a negative `minutesPerKm` seam → null (negative);
   - meridian 85 stops is valid (≈ 299.1);
   - meridian 86 stops → **null, not 300** (no clamp);
   - exactly at the guard is valid: 1 segment with seams `minutesPerKm: 0`, `minutesPerStop: 300` gives exactly 300.0 → ride 300.
8. **`estimateDirectJourney`:**
   - `parts = walkTo + ride + walkFrom`;
   - changing only one of the three changes `parts`;
   - a board or alight mismatch → null.
9. **Rounding:**
   - `roundUpToMultiple` on 4→5, 25→25, 26→30, 29→30, 30→30, 31→35, 147→150, 300→300;
   - every row of the §3.3 table via `DirectJourneyEstimate`;
   - a sweep asserting `parts ≤ shown < parts + 5` and `shown % 5 == 0` (walks 0–13 × rides 1–300 × the §3.3 fractions).

Then implement `journey_estimate.dart` and the constants. GREEN.

**T2 Card** (`journey_widget_test.dart`, new group; `buildTestApp`, GPS Bishan → VivoCity):
1. Suggested F20 shows `About 35 min · excl. waiting`. **Collapsed** alternatives F10 and F30 show their own trip lines
   without opening the steps.
2. Suggested shows `2 stops · ~31 min ride (est.)`. After "Show steps", F10 shows `3 stops · ~32 min ride (est.)` and
   F30 `3 stops · ~30 min ride (est.)`.
3. A meridian-based network (`FakeBusNetworkRepository(network: …)`) where the options' shown totals differ. Each
   option shows its own value from the §3.4 goldens.
4. Order in the summary column: title, then arrivals, then trip line. The trip line is present while arrivals load,
   after an arrivals failure (Retry visible) and when outdated. "Refresh arrivals" leaves it unchanged.
5. **Semantics:**
   - the trip line node's label is `Estimated trip, about 35 minutes, not including waiting`, with no header flag and
     no live region;
   - the bus step's label is `2 stops, about 31 minutes on the bus, estimated`;
   - the walk steps' semantics are unchanged.
6. **Footer:**
   - `tripEstimateNote` appears exactly once with a direct plan;
   - it is absent for walk-only, no direct bus and no nearby stops;
   - `estimateNote` is unchanged in every case.
7. **Missing data:** one option's ride has an unknown code. That option has no trip line and its step is plain
   `N stops`. The other options keep theirs, and Suggested and the order are unchanged.
8. **Walk-only:** no trip line or footer, and the bus network is never loaded (`bus.loads == 0`).
9. **Layout:** 360 dp and 320 dp × `TextScaler.linear(2.0)`, light and dark. No overflow, and the trip line is not
   clipped.
10. **Palettes:** for each of the 5 `AppPalette`s × light and dark, the trip line's colour is
    `colorScheme.onSurfaceVariant`. Its contrast against the Card colour is ≥ 4.5:1, computed from
    `computeLuminance`.

Then implement the card changes. GREEN.

**T3 Invariants** (`journey_estimate_invariants_test.dart`; guards proven by the §9 mutations):
1. **Ranking:** a fixture where option X has fewer segments but more km than option Y. `planDirectBus` keeps X first
   with `score == walks + 1.5 × stops` exactly. E2 would rank Y first, so the estimate is provably not in the ranking.
   Suggested is option 0.
2. **Arrivals:** with estimates shown, `FakeBusArrivalRepository.calls == {BSH2: 1, BSH1: 1}`. "Refresh arrivals"
   requests the same stops, and every estimate is unchanged.
3. **No geometry:** with the map closed and estimates shown, `FakeRouteGeometryRepository.loads == 0`. Opening the map
   gives exactly 1, as before E2.
4. **No new requests:** bus network `loads == 1` across a destination change. The endpoints in `app_config.dart` are
   unchanged, and the CSP test passes without edits.
5. **Imports** (a source scan, like `app_theme_test`):
   - `journey_estimate.dart` imports no Flutter, Riverpod, HTTP, `bus_arrival` or `features/map`;
   - `direct_bus_planner.dart` and `journey_providers.dart` do not import `journey_estimate.dart`;
   - no file in `lib/features/journey/` imports `features/map`.
6. **Selection:** selecting F10 keeps every trip line, and `bus.loads` is unchanged.

**T4 Integration.**
- `integration_test/happy_path_test.dart`: inside `journey-suggested`, the trip line `About 35 min · excl. waiting` is
  found; the footer is present; a walk-only journey, where already covered, has neither.
- Run on Android (`flutter test integration_test -d emulator-5558`) and on Web (`flutter drive
  --driver=test_driver/integration_test.dart --target=integration_test/happy_path_test.dart -d web-server
  --browser-name=chrome --profile`, chromedriver on :4444).

**T5 CI.** Add `test/features/journey/journey_estimate_test.dart` to the Linux Chrome step, and record that the
step passes in CI. The Windows Chrome runner is not used.

**T6 Docs** (§12) and the run log.

**T7 Gates.**
- Format, analyze and `flutter test` (CI).
- `flutter build web --release`, `flutter build apk --debug`, `flutter build apk --release` (debug-signed, as in
  Phase A).
- Android and Web integration.

**T8 Live verification** (§11).

**T9** Fresh review, frozen head, and a PR. It is **not merged** without the owner.

## 9. Mutation checks (each on `mut/e2-<id>`; CI run recorded; branch deleted)

| ID | Mutation | Must fail |
|---|---|---|
| M1 | Drop the ride from `partsMinutes` | T1.8, T1.9, T2.1 |
| M2 | Drop `walkToStopMinutes` | T1.8, T1.9 |
| M3 | Drop `walkFromStopMinutes` | T1.8, T1.9 |
| M4 | Add the estimate to the planner score in `_option` | T3.1 (and the existing planner score tests) |
| M5 | Straight board → alight distance instead of the hop sum | T1.3 |
| M6 | Sum from index 0 instead of `boardIndex` | T1.2, T1.4 |
| M7 | `stopCount + 1` segments | T1.1 |
| M8 | Swap the coefficients | T1.1, T1.5 |
| M9 | Round the total to the nearest 5, or down | T1.9 |
| M10 | Ride `floor` instead of `ceil` | T1.1 (3.519 → 3, not 4), T1.9 |
| M11 | Ride `round` instead of `ceil` | T1.1 (35.19 → 35, not 36), T1.9 sweep |
| M12 | Clamp to 300 instead of omitting | T1.7 (86 stops) |
| M13 | Remove the non-finite or negative guard | T1.7 |
| M14 | Card watches `busNetworkProvider` unconditionally | T2.8 |
| M15 | Card or estimator reads `routeGeometryProvider` | T3.3 |
| M16 | Remove a structural null guard (unknown code) | T1.7, T2.7 |
| M17 | Drop the trip line's `semanticsLabel` | T2.5 |
| M18 | Hard-code a colour (e.g. `Colors.grey`) on the trip line | `app_theme_test`, T2.10 |
| M19 | Show the trip line or footer on walk-only | T2.6, T2.8 |
| M20 | Trip line only on Suggested (not collapsed alternatives) | T2.1 |

## 10. Android and Web integration

- The same deterministic tests run on both platforms, with fakes only and no live API.
  - `initIntegrationTest()` first in every `main`; `pumpUntilFound` instead of `pumpAndSettle`.
- **Android:** `flutter test integration_test -d emulator-5558`.
- **Web:** `flutter drive … --profile` on `web-server`, one file per run.
- If either is blocked on this PC (Smart App Control or emulator memory), record **Not run** with the exact message.

## 11. Live verification (real services; recorded in `docs/testing.md`)

**Setup.**
- Chrome: `flutter run -d web-server --web-port 8766`. Ask the owner before stopping processes afterwards.
- Android: emulator-5558 with a Singapore location.

**Journeys.**
- Bishan Stn → Toa Payoh: 88 among the options.
- Tampines Int → VivoCity: long rides on 10 and 65.
- Tampines Int → 390 Tampines Ave 7: a loop (4, 19, 37).
- ION Orchard → Bugis Junction: two equal options.
- A walk-only pair, and Changi Village → Jurong Point (no direct bus): no estimate and no footer.

**Recompute check.** For one ride per platform, recompute offline from the card's own facts (service, board and
alight codes, stop count) with §3.1. The ride detail must equal `ceil(busExact)`, and the total must follow §3.2.

**Visual checks.**
- 360 px at 2× text.
- All 5 palettes, in light and dark.
- Reduced motion.
- The trip line reads as separate from "Next buses"; Refresh changes the ETAs only.

**Network panel.** No `routes.min.json` before "Show map", no new host, no CSP violation, and request counts as before
E2.

**Screen reader.**
- Web: check the semantics tree for both labels.
- Android: try TalkBack; if blocked, record Not run, as before.

## 12. Documentation updates (no historical Phase 1 or Phase 2 document is rewritten)

**`docs/assumptions.md`**
- Amend "Journey options": replace the sentence "No total journey time is shown: there is no in-vehicle time, so a
  total would be invented" with "Each direct-bus option shows a static trip estimate (see *Estimated trip time
  (E2)*)". Keep the rest of the row.
- Add the row **"Estimated trip time (E2)"**. It covers:
  - the formula and constants, with the stop definition (traversed segments = `BusOption.stops`) and the distance
    definition (consecutive-stop haversine, R 6,371,000 m, the planner's occurrence);
  - the rounding order of §3.2 and the rule "the total is the smallest multiple of 5 ≥ the displayed parts";
  - the frozen strings and semantics, and the footer;
  - the exclusions;
  - the validity rule (omit, never clamp; 300 min);
  - the §3.5 provenance in short: 11,914 rides, off-peak first and last trips, 462/730 of 798 directions, median
    3.4 / p90 12.9 min, below the schedule in 63 % of rides, no daytime or rush-hour evidence, applied to all
    directions as an extrapolation.

**`docs/data-sources.md`:** a new section, "Calibration evidence for E2 (offline only, not a runtime source)".
- What: LTA DataMall BusRoutes `WD_FirstBus` / `WD_LastBus`, under the SODL, with LTA attribution.
- How: read once on 2026-10-06 through busrouter's keyless `raw/bus-routes.datamall.json`, which is an undocumented
  intermediate file.
- Not loaded by the app, and no key was used.
- The scripts are not in the repository.

**`docs/architecture.md`:** a new section, "Post-submission enhancement E2: estimated trip time", with five ADRs:
- E2-1: model C on existing data, and its provenance;
- E2-2: display-only; planner, arrivals and map untouched;
- E2-3: computed in the card from the settled network, with no provider and no geometry;
- E2-4: the rounding order and wording;
- E2-5: a leg-level function, ready for E5 legs, with no leg types yet.

**`README.md`**
- A feature paragraph: an estimated trip time on each direct-bus option.
- Under Known limitations: "Trip times are rough estimates based on scheduled early/late bus timings, rounded up to
  5 minutes. They exclude waiting and live traffic conditions, and are not calibrated for daytime or rush-hour
  traffic."
- A link to this plan.

**`CLAUDE.md`**
- The Project paragraph names E2 after E1, E3 and E4, with this plan.
- Under Key flows, Journey: one sentence on `journey_estimate.dart`, the rounding order and display-only.
- Under Commands, CI: the Chrome step now also runs the estimator test.

**`docs/testing.md`:** run-log rows for:
- the baseline, and each RED and GREEN run;
- each mutation;
- the Chrome step, integration and gates;
- the live checks;
- Not run items.

## 13. Commit boundaries (implementation branch `feat/e2-static-journey-time`, after this plan PR is merged)

1. `test(journey): E2 estimator goldens, validity and rounding thresholds (RED)`
2. `feat(journey): static E2 bus-leg and direct-journey estimate`
3. `test(journey): E2 trip line, ride step, footer, semantics, layout, palettes (RED)`
4. `feat(journey): show the E2 estimate on direct-bus options`
5. `test(journey): E2 invariants: ranking, arrivals, geometry, requests, imports`
6. `test(integration): E2 trip line on the happy path`
7. `ci: run the E2 estimator test on Linux Chrome`
8. `docs: E2 assumptions, data sources, ADRs, README, CLAUDE.md`
9. `docs(testing): E2 run log and evidence`

These are small commits, with no force-push or history rewrite. A mutation never lands on the feature branch.

## 14. Risks and stop conditions

**Risks.**
1. **Read as an ETA.** Mitigated by "excl. waiting", rounding up to 5, a separate lighter line below the arrivals, and
   no clock time. Owner review at T8.
2. **Daytime and rush-hour underestimate.** The model is off-peak calibrated and below the schedule in 63 % of test
   rides. The footer and README say it is a rough estimate from early and late timings. There is no uplift (frozen).
3. **Extrapolation** to directions excluded from calibration. Express and City Direct have larger errors.
4. **Text collision in existing tests.** `arrivals_widget_test.dart` asserts `find.textContaining('0 min')` finds
   nothing. With the fakes, the built texts are `About 35 min` and `~31 min ride`. F30's `~30 min ride` exists only
   after "Show steps", which those tests don't press. If any existing test fails, stop.
5. **Footer interpretation** (§2): needs confirmation before T2.
6. **Clutter at 2× text:** one extra wrapped line per option.

**Stop conditions.**
- `main` moved and the journey, arrivals or map files changed.
- Any existing test needs an edit.
- A T3 invariant fails.
- The 2× layout cannot be fixed without restructuring the card.
- The estimate needs `routes.min.json`, a provider, planner or arrivals change, or a dependency.
- The live check shows confusion with arrivals.
- The CI suite count changes unexpectedly.

## 15. Compatibility with future E5 bus legs

- `estimateBusMinutes(network, service:, direction:, boardIndex:, stopCount:)` is an E5 bus leg's own fields, so each
  leg can be estimated with no E2 change.
- `roundUpToMultiple` is reusable for any future total.
- `DirectJourneyEstimate` stays direct-only. E2 adds no transfer total, wait component or leg sequence; those are
  E5 decisions (E5 report P3).
- If E5 adopts the leg-sequence model recommended by the E6 addendum, this function is its bus-leg duration.

## 16. Decisions

Q1–Q10 are frozen (§2). One point remains for review: **the footer interpretation** in §2 (one added E2 line; the
walking note stays).
